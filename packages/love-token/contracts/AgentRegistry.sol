// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAgentRegistry.sol";
import "./LOVE.sol";

/**
 * @title AgentRegistry
 * @author LoveLogicAI
 * @notice Manages agent lifecycle: registration, reputation, slashing.
 *
 * Agents must register to earn $LOVE rewards. Reputation (0-1000) gates
 * access to higher-value tasks. Slashing burns staked $LOVE when agents
 * produce verified bad output or fail verification.
 *
 * SAK Sovereignty Layer Mapping:
 *   L1 Persistent Identity → agentId (permanent on-chain identity)
 *   L2 Owned Inference → reputation gates inference priority
 *   L3 P&L Accountability → slashing enforces economic accountability
 *   L4 Sub-Agent Marketplace → only registered agents can participate
 */
contract AgentRegistry is IAgentRegistry, Ownable, ReentrancyGuard {
    LOVE public loveToken;

    mapping(address => Agent) public agents;
    mapping(bytes32 => address) public agentIdToWallet;
    address[] public agentList;
    uint256 public constant BASE_REPUTATION = 500;
    uint256 public constant MAX_REPUTATION = 1000;
    uint256 public constant MIN_REPUTATION = 0;
    uint256 public constant SLASH_REPUTATION_PENALTY = 50;

    // Slashing threshold: below this reputation, agent is auto-deactivated
    uint256 public constant DEACTIVATION_THRESHOLD = 100;

    constructor(address _loveToken) Ownable(msg.sender) {
        loveToken = LOVE(_loveToken);
    }

    function registerAgent(address _wallet, bytes32 _agentId) external onlyOwner {
        require(_wallet != address(0), "Invalid wallet");
        require(!agents[_wallet].active, "Already registered");
        require(agentIdToWallet[_agentId] == address(0), "Agent ID taken");

        agents[_wallet] = Agent({
            wallet: _wallet,
            agentId: _agentId,
            registeredAt: block.timestamp,
            reputation: BASE_REPUTATION,
            active: true,
            totalEarned: 0,
            totalSlashed: 0
        });

        agentIdToWallet[_agentId] = _wallet;
        agentList.push(_wallet);

        emit AgentRegistered(_wallet, _agentId, BASE_REPUTATION);
    }

    function deactivateAgent(address _wallet) external onlyOwner {
        require(agents[_wallet].active, "Not active");
        agents[_wallet].active = false;
        emit AgentDeactivated(_wallet, agents[_wallet].agentId);
    }

    function slashAgent(address _wallet, string calldata _reason) external onlyOwner nonReentrant {
        require(agents[_wallet].active, "Agent not active");

        // Slash staked LOVE
        loveToken.slash(_wallet, _reason);

        // Reduce reputation
        uint256 newRep = agents[_wallet].reputation > SLASH_REPUTATION_PENALTY
            ? agents[_wallet].reputation - SLASH_REPUTATION_PENALTY
            : 0;
        agents[_wallet].reputation = newRep;
        agents[_wallet].totalSlashed += 1;

        emit AgentSlashed(_wallet, 0, _reason);

        // Auto-deactivate if reputation drops below threshold
        if (newRep < DEACTIVATION_THRESHOLD) {
            agents[_wallet].active = false;
            emit AgentDeactivated(_wallet, agents[_wallet].agentId);
        }

        emit ReputationUpdated(_wallet, newRep);
    }

    function updateReputation(address _wallet, uint256 _delta, bool _increase) external onlyOwner {
        require(agents[_wallet].active, "Agent not active");

        uint256 newRep;
        if (_increase) {
            newRep = agents[_wallet].reputation + _delta > MAX_REPUTATION
                ? MAX_REPUTATION
                : agents[_wallet].reputation + _delta;
        } else {
            newRep = agents[_wallet].reputation > _delta
                ? agents[_wallet].reputation - _delta
                : 0;
        }
        agents[_wallet].reputation = newRep;
        emit ReputationUpdated(_wallet, newRep);
    }

    function isRegisteredAgent(address _wallet) external view returns (bool) {
        return agents[_wallet].active;
    }

    function getAgent(address _wallet) external view returns (Agent memory) {
        return agents[_wallet];
    }

    function getActiveAgents() external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < agentList.length; i++) {
            if (agents[agentList[i]].active) count++;
        }

        address[] memory active = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < agentList.length; i++) {
            if (agents[agentList[i]].active) {
                active[idx++] = agentList[i];
            }
        }
        return active;
    }

    function recordEarnings(address _wallet, uint256 _amount) external onlyOwner {
        agents[_wallet].totalEarned += _amount;
    }

    function getAgentCount() external view returns (uint256) {
        return agentList.length;
    }
}
