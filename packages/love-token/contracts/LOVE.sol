// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LOVE Token
 * @author LoveLogicAI
 * @notice Native currency for the Sovereign Agent Kernel (SAK) ecosystem.
 *         Agents earn LOVE for task completion; spend it on inference and sub-agent hires.
 *         On-chain P&L proofs are settled in LOVE.
 *
 * Tokenomics:
 *   - Total Supply: 1,000,000,000 LOVE (1 billion)
 *   - Decimals: 18
 *   - Agent Reward Pool: 40% (400M) — emitted to agents for task completion
 *   - Team: 15% (150M) — 2yr vest, 6mo cliff
 *   - Treasury: 20% (200M) — governance-controlled
 *   - Liquidity: 10% (100M) — DEX liquidity provisioning
 *   - Community: 10% (100M) — airdrops, grants, build-in-public rewards
 *   - Partnership: 5% (50M) — integrations, exchanges
 *
 * Emission: Agent reward pool emits via merkle root claims (epoch-based).
 *           Each epoch (7 days), a new merkle root is committed by the owner
 *           (later: governance). Agents claim their earned LOVE per epoch.
 */
contract LOVE is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    // --- Allocation constants (in raw units, 18 decimals) ---
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant AGENT_REWARD_POOL = 400_000_000 * 1e18;
    uint256 public constant TEAM_ALLOCATION = 150_000_000 * 1e18;
    uint256 public constant TREASURY = 200_000_000 * 1e18;
    uint256 public constant LIQUIDITY = 100_000_000 * 1e18;
    uint256 public constant COMMUNITY = 100_000_000 * 1e18;
    uint256 public constant PARTNERSHIP = 50_000_000 * 1e18;

    // --- Epoch-based agent rewards (merkle claim) ---
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

    // --- Events ---
    event EpochCommitted(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalAllocated);
    event EpochClaimed(address indexed agent, uint256 indexed epoch, uint256 amount);
    event RewardsDistributed(address indexed agent, uint256 amount);

    constructor(
        address _teamWallet,
        address _treasuryWallet,
        address _liquidityWallet,
        address _communityWallet,
        address _partnershipWallet
    ) ERC20("LOVE", "LOVE") ERC20Permit("LOVE") Ownable(msg.sender) {
        epochStartTime = block.timestamp;

        // Mint all allocations upfront
        _mint(_teamWallet, TEAM_ALLOCATION);
        _mint(_treasuryWallet, TREASURY);
        _mint(_liquidityWallet, LIQUIDITY);
        _mint(_communityWallet, COMMUNITY);
        _mint(_partnershipWallet, PARTNERSHIP);

        // Agent reward pool stays with contract for epoch-based emission
        _mint(address(this), AGENT_REWARD_POOL);
    }

    // --- Epoch management ---

    function commitEpoch(bytes32 _merkleRoot, uint256 _totalAllocated) external onlyOwner {
        require(_totalAllocated <= getRemainingRewardPool(), "Exceeds remaining reward pool");
        require(!epochs[currentEpoch].committed, "Current epoch already committed");

        epochs[currentEpoch] = Epoch({
            merkleRoot: _merkleRoot,
            totalAllocated: _totalAllocated,
            committed: true
        });

        emit EpochCommitted(currentEpoch, _merkleRoot, _totalAllocated);
    }

    function advanceEpoch() external onlyOwner {
        require(block.timestamp >= epochStartTime + (currentEpoch + 1) * EPOCH_DURATION, "Epoch not over yet");
        currentEpoch++;
    }

    // --- Agent reward claims (merkle proof) ---

    function claimRewards(
        uint256 _epoch,
        uint256 _amount,
        bytes32[] calldata _proof
    ) external {
        Epoch storage e = epochs[_epoch];
        require(e.committed, "Epoch not committed");
        require(!claimedEpoch[_epoch][msg.sender], "Already claimed this epoch");

        // Verify merkle proof: keccak256(abi.encodePacked(msg.sender, _amount))
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(_verifyProof(_proof, e.merkleRoot, leaf), "Invalid merkle proof");

        claimedEpoch[_epoch][msg.sender] = true;
        _transfer(address(this), msg.sender, _amount);

        emit EpochClaimed(msg.sender, _epoch, _amount);
        emit RewardsDistributed(msg.sender, _amount);
    }

    // --- View functions ---

    function getRemainingRewardPool() public view returns (uint256) {
        return balanceOf(address(this));
    }

    function getCurrentEpoch() external view returns (uint256) {
        return currentEpoch;
    }

    function getEpochEndTime() external view returns (uint256) {
        return epochStartTime + (currentEpoch + 1) * EPOCH_DURATION;
    }

    // --- Internal: merkle verification ---

    function _verifyProof(
        bytes32[] calldata _proof,
        bytes32 _root,
        bytes32 _leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;
        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];
            if (computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        return computedHash == _root;
    }
}
