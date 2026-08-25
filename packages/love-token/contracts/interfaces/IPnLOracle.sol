// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPnLOracle
 * @notice Interface for the P&L Oracle — computes agent rewards from on-chain P&L data.
 *
 * The oracle receives P&L reports from the SAK orchestrator (off-chain),
 * verifies them, and commits epoch merkle roots to the LOVE token contract.
 *
 * P&L Formula:
 *   reward = baseReward + (pnl * performanceMultiplier) - (stake * riskAdjustment)
 *   where performanceMultiplier scales with agent reputation
 */
interface IPnLOracle {
    struct PnLReport {
        address agent;
        int256 pnl;              // Profit (positive) or Loss (negative)
        uint256 tasksCompleted;
        uint256 gasConsumed;     // Gas spent by agent (deducted from reward)
        uint256 timestamp;
        bytes signature;         // SAK orchestrator signature for verification
    }

    struct EpochSummary {
        uint256 epoch;
        uint256 totalPnL;        // Aggregate P&L (absolute value sum)
        uint256 totalTasks;
        uint256 totalAgents;
        bytes32 merkleRoot;
        uint256 totalAllocated;
    }

    event PnLReported(address indexed agent, int256 pnl, uint256 tasksCompleted);
    event EpochFinalized(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalAllocated);

    function reportPnL(PnLReport calldata _report) external;
    function finalizeEpoch() external returns (bytes32 merkleRoot, uint256 totalAllocated);
    function getEpochSummary(uint256 _epoch) external view returns (EpochSummary memory);
    function verifyReport(PnLReport calldata _report) external view returns (bool);
}
