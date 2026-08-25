// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./interfaces/IPnLOracle.sol";
import "./LOVE.sol";
import "./AgentRegistry.sol";

/**
 * @title PnLOracle
 * @author LoveLogicAI
 * @notice Computes agent rewards from on-chain P&L data and commits
 *         epoch merkle roots to the LOVE token contract.
 *
 * Reward Formula:
 *   baseReward = EPOCH_BASE_REWARD * (reputation / 1000)
 *   pnlBonus = max(0, pnl) * PNL_MULTIPLIER
 *   gasCost = gasConsumed * GAS_PRICE_ORACLE
 *   reward = baseReward + pnlBonus - gasCost
 *   reward = clamp(reward, 0, MAX_REWARD_PER_AGENT)
 *
 * The merkle tree is: leaf = keccak256(abi.encodePacked(agent, reward))
 * SAK orchestrator signs each P&L report off-chain and submits to this oracle.
 */
contract PnLOracle is IPnLOracle, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    LOVE public loveToken;
    AgentRegistry public agentRegistry;

    // --- Config ---
    uint256 public constant EPOCH_BASE_REWARD = 50_000 * 1e18; // 50k LOVE base per epoch
    uint256 public constant PNL_MULTIPLIER_BPS = 100; // 1x P&L (100 bps = 1.0x)
    uint256 public constant MAX_REWARD_PER_AGENT = 500_000 * 1e18; // 500k LOVE max per epoch
    uint256 public constant GAS_PRICE_ORACLE = 1 gwei; // approx Base gas price

    // --- Orchestrator ---
    address public orchestrator; // SAK orchestrator signing P&L reports

    // --- Epoch state ---
    mapping(uint256 => PnLReport[]) public epochReports;
    mapping(uint256 => EpochSummary) public epochSummaries;
    uint256[] public finalizedEpochs;

    // --- Events ---
    event OrchestratorUpdated(address indexed oldOrchestrator, address indexed newOrchestrator);

    constructor(address _loveToken, address _agentRegistry, address _orchestrator) Ownable(msg.sender) {
        loveToken = LOVE(_loveToken);
        agentRegistry = AgentRegistry(_agentRegistry);
        orchestrator = _orchestrator;
    }

    // --- P&L Reporting ---

    function reportPnL(PnLReport calldata _report) external override {
        require(verifyReport(_report), "Invalid report signature");
        require(agentRegistry.isRegisteredAgent(_report.agent), "Agent not registered");
        require(block.timestamp >= loveToken.epochStartTime() + (loveToken.currentEpoch()) * loveToken.EPOCH_DURATION(), "Report for past epoch");

        epochReports[loveToken.currentEpoch()].push(_report);
        emit PnLReported(_report.agent, _report.pnl, _report.tasksCompleted);
    }

    // --- Epoch Finalization ---

    function finalizeEpoch() external override onlyOwner nonReentrant returns (bytes32 merkleRoot, uint256 totalAllocated) {
        uint256 epoch = loveToken.currentEpoch();
        PnLReport[] storage reports = epochReports[epoch];

        require(reports.length > 0, "No reports for epoch");
        require(epochSummaries[epoch].totalAllocated == 0, "Epoch already finalized");

        uint256 totalPnL = 0;
        uint256 totalTasks = 0;
        bytes32[] memory leaves = new bytes32[](reports.length);

        for (uint256 i = 0; i < reports.length; i++) {
            PnLReport memory r = reports[i];

            // Compute reward
            uint256 baseReward = (EPOCH_BASE_REWARD * agentRegistry.getAgent(r.agent).reputation) / 1000;
            uint256 pnlBonus = r.pnl > 0 ? uint256(int256(r.pnl)) * PNL_MULTIPLIER_BPS / 10000 : 0;
            uint256 gasCost = r.gasConsumed * GAS_PRICE_ORACLE;

            uint256 reward = baseReward + pnlBonus;
            reward = reward > gasCost ? reward - gasCost : 0;
            if (reward > MAX_REWARD_PER_AGENT) reward = MAX_REWARD_PER_AGENT;

            totalPnL += uint256(int256(r.pnl < 0 ? int256(0) - r.pnl : r.pnl));
            totalTasks += r.tasksCompleted;
            totalAllocated += reward;

            leaves[i] = keccak256(abi.encodePacked(r.agent, reward));
        }

        // Build merkle root (simple sorted pairs)
        merkleRoot = _buildMerkleRoot(leaves);

        // Commit to LOVE token
        loveToken.commitEpoch(merkleRoot, totalAllocated);

        epochSummaries[epoch] = EpochSummary({
            epoch: epoch,
            totalPnL: totalPnL,
            totalTasks: totalTasks,
            totalAgents: reports.length,
            merkleRoot: merkleRoot,
            totalAllocated: totalAllocated
        });

        finalizedEpochs.push(epoch);

        emit EpochFinalized(epoch, merkleRoot, totalAllocated);
    }

    // --- Verification ---

    function verifyReport(PnLReport calldata _report) public view override returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            _report.agent,
            _report.pnl,
            _report.tasksCompleted,
            _report.gasConsumed,
            _report.timestamp
        ));
        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();
        address recovered = ECDSA.recover(ethSignedHash, _report.signature);
        return recovered == orchestrator;
    }

    function getEpochSummary(uint256 _epoch) external view override returns (EpochSummary memory) {
        return epochSummaries[_epoch];
    }

    function getEpochReportCount(uint256 _epoch) external view returns (uint256) {
        return epochReports[_epoch].length;
    }

    // --- Admin ---

    function setOrchestrator(address _newOrchestrator) external onlyOwner {
        emit OrchestratorUpdated(orchestrator, _newOrchestrator);
        orchestrator = _newOrchestrator;
    }

    // --- Internal: merkle root ---

    function _buildMerkleRoot(bytes32[] memory _leaves) internal pure returns (bytes32) {
        if (_leaves.length == 0) return bytes32(0);
        if (_leaves.length == 1) return _leaves[0];

        uint256 n = _leaves.length;
        while (n > 1) {
            uint256 half = (n + 1) / 2;
            for (uint256 i = 0; i < half; i++) {
                bytes32 a = _leaves[i * 2];
                bytes32 b = (i * 2 + 1 < n) ? _leaves[i * 2 + 1] : _leaves[0]; // pad with first leaf
                _leaves[i] = a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
            }
            n = half;
        }
        return _leaves[0];
    }
}
