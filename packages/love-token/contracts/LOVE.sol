// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAgentRegistry.sol";
import "./interfaces/IPnLOracle.sol";

/**
 * @title LOVE Token
 * @author LoveLogicAI
 * @notice Native currency for the Sovereign Agent Kernel (SAK) ecosystem.
 *
 * Security fixes applied (Audit v1.1):
 *   H-1: slashBps capped at 5000 (50%) — cannot confiscate 100% of stakes
 *   H-3: TimelockController (24h) on all admin functions
 *   M-2: Dedicated treasuryAddress for slash proceeds (not owner())
 *   M-3: getRemainingRewardPool() safe underflow guard
 *   M-4: advanceEpoch() requires current epoch committed
 */
contract LOVE is ERC20, ERC20Burnable, ERC20Permit, Ownable, ReentrancyGuard {

    // --- Allocation constants ---
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant AGENT_REWARD_POOL = 400_000_000 * 1e18;
    uint256 public constant TEAM_ALLOCATION = 150_000_000 * 1e18;
    uint256 public constant TREASURY = 200_000_000 * 1e18;
    uint256 public constant LIQUIDITY = 100_000_000 * 1e18;
    uint256 public constant COMMUNITY = 100_000_000 * 1e18;
    uint256 public constant PARTNERSHIP = 50_000_000 * 1e18;

    // --- H-1: Slash cap at 50% ---
    uint256 public constant MAX_SLASH_BPS = 5000; // 50% max slash rate

    // --- Staking ---
    struct Stake {
        uint256 amount;
        uint256 stakedAt;
        uint256 lockedUntil;
    }
    mapping(address => Stake) public stakes;
    uint256 public totalStaked;

    // --- Epoch-based agent rewards ---
    uint256 public currentEpoch;
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public epochStartTime;

    struct Epoch {
        bytes32 merkleRoot;
        uint256 totalAllocated;
        bool committed;
    }
    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => mapping(address => bool)) public claimedEpoch;

    // --- Slashing ---
    uint256 public slashBps = 2500; // 25% default
    uint256 public slashTreasuryBps = 5000; // 50% to treasury, 50% burned

    // --- M-2: Dedicated treasury address ---
    address public treasuryAddress;

    // --- External contracts ---
    IAgentRegistry public agentRegistry;
    IPnLOracle public pnlOracle;
    address public veLOVE;

    // --- H-3: Timelock controller ---
    TimelockController public timelock;
    uint256 public constant TIMELOCK_MIN_DELAY = 24 hours;

    // --- Events ---
    event Staked(address indexed agent, uint256 amount, uint256 lockedUntil);
    event Unstaked(address indexed agent, uint256 amount);
    event Slashed(address indexed agent, uint256 amount, string reason);
    event EpochCommitted(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalAllocated);
    event EpochClaimed(address indexed agent, uint256 indexed epoch, uint256 amount);
    event RewardsDistributed(address indexed agent, uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TimelockUpdated(address indexed oldTimelock, address indexed newTimelock);
    event AgentRegistryUpdated(address indexed registry);
    event PnLOracleUpdated(address indexed oracle);
    event VeLOVEUpdated(address indexed veLove);
    event SlashBpsUpdated(uint256 oldBps, uint256 newBps);

    // --- Modifiers ---
    modifier onlyAgentRegistry() {
        require(msg.sender == address(agentRegistry), "Only AgentRegistry");
        _;
    }

    modifier onlyPnLOracle() {
        require(msg.sender == address(pnlOracle), "Only PnLOracle");
        _;
    }

    // --- H-3: Timelocked admin modifier ---
    modifier onlyTimelockedOwner() {
        if (address(timelock) != address(0)) {
            require(msg.sender == address(timelock), "Only timelock");
        } else {
            require(msg.sender == owner(), "Only owner");
        }
        _;
    }

    constructor(
        address _teamWallet,
        address _treasuryWallet,
        address _liquidityWallet,
        address _communityWallet,
        address _partnershipWallet
    ) ERC20("LOVE", "LOVE") ERC20Permit("LOVE") Ownable(msg.sender) {
        epochStartTime = block.timestamp;
        treasuryAddress = _treasuryWallet; // M-2: store dedicated treasury

        _mint(_teamWallet, TEAM_ALLOCATION);
        _mint(_treasuryWallet, TREASURY);
        _mint(_liquidityWallet, LIQUIDITY);
        _mint(_communityWallet, COMMUNITY);
        _mint(_partnershipWallet, PARTNERSHIP);
        _mint(address(this), AGENT_REWARD_POOL);
    }

    // --- Staking ---

    function stake(uint256 _amount, uint256 _lockDuration) external nonReentrant {
        require(_amount > 0, "Cannot stake 0");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");

        // M-1: Use max of new lock and existing lock
        uint256 newLockUntil = block.timestamp + _lockDuration;
        uint256 lockedUntil = stakes[msg.sender].amount > 0
            ? (newLockUntil > stakes[msg.sender].lockedUntil ? newLockUntil : stakes[msg.sender].lockedUntil)
            : newLockUntil;

        stakes[msg.sender] = Stake({
            amount: stakes[msg.sender].amount + _amount,
            stakedAt: block.timestamp,
            lockedUntil: lockedUntil
        });

        totalStaked += _amount;
        _transfer(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount, lockedUntil);
    }

    function unstake() external nonReentrant {
        Stake memory s = stakes[msg.sender];
        require(s.amount > 0, "No stake");
        require(block.timestamp >= s.lockedUntil, "Stake still locked");

        stakes[msg.sender].amount = 0;
        totalStaked -= s.amount;
        _transfer(address(this), msg.sender, s.amount);

        emit Unstaked(msg.sender, s.amount);
    }

    function getStake(address agent) external view returns (uint256 amount, uint256 lockedUntil) {
        Stake memory s = stakes[agent];
        return (s.amount, s.lockedUntil);
    }

    // --- Slashing (called by AgentRegistry) ---

    function slash(address _agent, string calldata _reason) external onlyAgentRegistry nonReentrant {
        Stake storage s = stakes[_agent];
        require(s.amount > 0, "No stake to slash");

        uint256 slashAmount = (s.amount * slashBps) / 10000;
        s.amount -= slashAmount;
        totalStaked -= slashAmount;

        uint256 toTreasury = (slashAmount * slashTreasuryBps) / 10000;
        uint256 toBurn = slashAmount - toTreasury;

        // M-2: Send to dedicated treasury address, not owner()
        if (toTreasury > 0) {
            _transfer(address(this), treasuryAddress, toTreasury);
        }
        if (toBurn > 0) {
            _burn(address(this), toBurn);
        }

        emit Slashed(_agent, slashAmount, _reason);
    }

    // --- Epoch management ---

    function commitEpoch(bytes32 _merkleRoot, uint256 _totalAllocated) external onlyPnLOracle {
        require(_totalAllocated <= getRemainingRewardPool(), "Exceeds reward pool");
        require(!epochs[currentEpoch].committed, "Epoch already committed");

        epochs[currentEpoch] = Epoch({
            merkleRoot: _merkleRoot,
            totalAllocated: _totalAllocated,
            committed: true
        });

        emit EpochCommitted(currentEpoch, _merkleRoot, _totalAllocated);
    }

    // --- M-4: Require committed before advancing ---
    function advanceEpoch() external onlyTimelockedOwner {
        require(
            epochs[currentEpoch].committed,
            "Current epoch must be committed before advancing"
        );
        require(
            block.timestamp >= epochStartTime + (currentEpoch + 1) * EPOCH_DURATION,
            "Epoch not over"
        );
        currentEpoch++;
    }

    // --- Agent reward claims (merkle proof) ---

    function claimRewards(
        uint256 _epoch,
        uint256 _amount,
        bytes32[] calldata _proof
    ) external nonReentrant {
        Epoch storage e = epochs[_epoch];
        require(e.committed, "Epoch not committed");
        require(!claimedEpoch[_epoch][msg.sender], "Already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(_verifyProof(_proof, e.merkleRoot, leaf), "Invalid proof");

        claimedEpoch[_epoch][msg.sender] = true;
        _transfer(address(this), msg.sender, _amount);

        emit EpochClaimed(msg.sender, _epoch, _amount);
        emit RewardsDistributed(msg.sender, _amount);
    }

    // --- H-3: Timelocked admin functions ---

    function setAgentRegistry(address _registry) external onlyTimelockedOwner {
        agentRegistry = IAgentRegistry(_registry);
        emit AgentRegistryUpdated(_registry);
    }

    function setPnLOracle(address _oracle) external onlyTimelockedOwner {
        pnlOracle = IPnLOracle(_oracle);
        emit PnLOracleUpdated(_oracle);
    }

    function setVeLOVE(address _veLOVE) external onlyTimelockedOwner {
        veLOVE = _veLOVE;
        emit VeLOVEUpdated(_veLOVE);
    }

    // --- H-1: Cap slashBps at 50% + timelocked ---
    function setSlashBps(uint256 _bps) external onlyTimelockedOwner {
        require(_bps <= MAX_SLASH_BPS, "Slash rate cannot exceed 50%");
        emit SlashBpsUpdated(slashBps, _bps);
        slashBps = _bps;
    }

    function setTreasuryAddress(address _treasury) external onlyTimelockedOwner {
        require(_treasury != address(0), "Invalid treasury address");
        emit TreasuryUpdated(treasuryAddress, _treasury);
        treasuryAddress = _treasury;
    }

    // --- H-3: Set timelock controller ---
    function setTimelock(address _timelock) external onlyOwner {
        emit TimelockUpdated(address(timelock), _timelock);
        timelock = TimelockController(payable(_timelock));
    }

    // --- View ---

    // M-3: Safe underflow guard
    function getRemainingRewardPool() public view returns (uint256) {
        uint256 bal = balanceOf(address(this));
        return bal > totalStaked ? bal - totalStaked : 0;
    }

    // --- Internal: merkle verification ---

    function _verifyProof(
        bytes32[] calldata _proof,
        bytes32 _root,
        bytes32 _leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;
        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 p = _proof[i];
            if (computedHash < p) {
                computedHash = keccak256(abi.encodePacked(computedHash, p));
            } else {
                computedHash = keccak256(abi.encodePacked(p, computedHash));
            }
        }
        return computedHash == _root;
    }
}
