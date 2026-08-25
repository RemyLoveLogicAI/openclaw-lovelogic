// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAgentRegistry
 * @notice Interface for agent registration, staking, and slashing.
 *         The registry is the gatekeeper — only registered agents can earn epoch rewards.
 */
interface IAgentRegistry {
    struct Agent {
        address wallet;
        bytes32 agentId;      // SAK agent identifier (e.g., keccak256("sak:agent:001"))
        uint256 registeredAt;
        uint256 reputation;    // Slashable reputation score (0-1000, starts at 500)
        bool active;
        uint256 totalEarned;   // Lifetime $LOVE earned
        uint256 totalSlashed;  // Lifetime $LOVE slashed
    }

    event AgentRegistered(address indexed wallet, bytes32 agentId, uint256 reputation);
    event AgentDeactivated(address indexed wallet, bytes32 agentId);
    event AgentSlashed(address indexed wallet, uint256 slashAmount, string reason);
    event ReputationUpdated(address indexed wallet, uint256 newReputation);

    function registerAgent(address _wallet, bytes32 _agentId) external;
    function deactivateAgent(address _wallet) external;
    function slashAgent(address _wallet, string calldata _reason) external;
    function updateReputation(address _wallet, uint256 _delta, bool _increase) external;
    function isRegisteredAgent(address _wallet) external view returns (bool);
    function getAgent(address _wallet) external view returns (Agent memory);
    function getActiveAgents() external view returns (address[] memory);
}
