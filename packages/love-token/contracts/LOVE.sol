// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAgentRegistry.sol";
import "./interfaces/IPnLOracle.sol";

/**
 * @title LOVE Token
 * @author LoveLogicAI
 * @notice Native currency for the Sovereign Agent Kernel (SAK) ecosystem.
 *
 * Architecture:
 *   LOVE (ERC-20) ← veLOVE (governance escrow)
 *       ↑↓               ↑↓
 *   AgentRegistry ← PnLOracle
 *   (stake/slash)   (P&L → epoch rewards)
 *
 * Tokenomics:
 *   Total Supply: 1,000,000,000 LOVE (1 billion)
 *   Agent Reward Pool: 40% (400M) — epoch-based merkle emission
 *   Team: 15% (150M) — 2yr vest, 6mo cliff
 *   Treasury: 20% (200M) — veLOVE governance
 *   Liquidity: 10% (100M) — DEX LP
 *   Community: 10% (100M) — airdrops, grants
 *   Partnership: 5% (50M) — integrations
 *
 * Innovations:
 *   1. Epoch-based merkle emission — gas-efficient agent reward distribution
 *   2. Agent staking with slashing — economic accountability for agent behavior
 *   3. On-chain P&L oracle — agents report profit/loss, verifiable by anyone
 *   4. veLOVE governance — lock LOVE for boosted rewards + voting power
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
    uint256 public slashBps = 2500; // 25% of stake slashed per violation
    uint256 public slashTreasuryBps = 5000; // 50% of slashed funds go to treasury, 50% burned

    // --- External contracts ---
    IAgentRegistry public agentRegistry;
    IPnLOracle public pnlOracle;
    address public veLOVE; // governance escrow contract

    // --- Events ---
    event Staked(address indexed agent, uint256 amount, uint256 lockedUntil);
    event Unstaked(address indexed agent, uint256 amount);
    event Slashed(address indexed agent, uint256 amount, string reason);
    event EpochCommitted(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalAllocated);
    event EpochClaimed(address indexed agent, uint256 indexed epoch, uint256 amount);
    event RewardsDistributed(address indexed agent, uint256 amount);

    // --- Modifiers ---
    modifier onlyAgentRegistry() {
        require(msg.sender == address(agentRegistry), "Only AgentRegistry");
        _;
    }

    modifier onlyPnLOracle() {
        require(msg.sender == address(pnlOracle), "Only PnLOracle");
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

        uint256 lockedUntil = block.timestamp + _lockDuration;
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

        if (toTreasury > 0) {
            _transfer(address(this), owner(), toTreasury);
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

    function advanceEpoch() external onlyOwner {
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

    // --- Admin: set external contracts ---

    function setAgentRegistry(address _registry) external onlyOwner {
        agentRegistry = IAgentRegistry(_registry);
    }

    function setPnLOracle(address _oracle) external onlyOwner {
        pnlOracle = IPnLOracle(_oracle);
    }

    function setVeLOVE(address _veLOVE) external onlyOwner {
        veLOVE = _veLOVE;
    }

    function setSlashBps(uint256 _bps) external onlyOwner {
        require(_bps <= 10000, "Cannot exceed 100%");
        slashBps = _bps;
    }

    // --- View ---

    function getRemainingRewardPool() public view returns (uint256) {
        return balanceOf(address(this)) - totalStaked;
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
