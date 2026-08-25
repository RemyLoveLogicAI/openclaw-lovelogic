// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title veLOVE — Vested Escrow LOVE
 * @author LoveLogicAI
 * @notice Lock LOVE to receive veLOVE (non-transferable governance token).
 *         Longer locks = more voting power. Based on Curve's veCRV model.
 *
 * Why veLOVE matters for the agent economy:
 *   1. Agents lock LOVE → get boosted epoch rewards (up to 2.5x)
 *   2. veLOVE holders govern the treasury (200M LOVE)
 *   3. Agents with veLOVE get priority in the Sub-Agent Marketplace (L4)
 *   4. Long locks signal commitment → reputation boost in AgentRegistry
 *
 * Voting Power Formula:
 *   veLOVE_balance = LOVE_locked * (lock_duration / MAX_LOCK) * BOOST_FACTOR
 *   where MAX_LOCK = 4 years, BOOST_FACTOR = 1.0
 *   so 1 LOVE locked for 4 years = 1 veLOVE
 *   and 1 LOVE locked for 1 year = 0.25 veLOVE
 *
 * veLOVE decays linearly as the lock approaches expiry.
 */
contract veLOVE is Ownable, ReentrancyGuard {
    IERC20 public loveToken;

    struct Lock {
        uint256 amount;
        uint256 lockedAt;
        uint256 unlockAt;     // timestamp when lock expires
        uint256 maxLock;      // original lock duration (for boost calc)
    }

    mapping(address => Lock) public locks;
    uint256 public constant MAX_LOCK = 4 * 365 days;
    uint256 public constant MIN_LOCK = 7 days;
    uint256 public constant BOOST_NUMERATOR = 1e18;
    uint256 public constant BOOST_DENOMINATOR = 1e18;
    uint256 public constant REWARD_BOOST_MAX_BPS = 25000; // 2.5x max boost

    // Governance
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 votingDeadline;
        bool executed;
    }
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 7 days;

    // Events
    event Locked(address indexed user, uint256 amount, uint256 unlockAt);
    event Unlocked(address indexed user, uint256 amount);
    event LockExtended(address indexed user, uint256 newUnlockAt);
    event Voted(address indexed voter, uint256 indexed proposalId, bool support, uint256 weight);
    event ProposalCreated(uint256 indexed id, address proposer, string description);
    event ProposalExecuted(uint256 indexed id);

    constructor(address _loveToken) Ownable(msg.sender) {
        loveToken = IERC20(_loveToken);
    }

    // --- Locking ---

    function lock(uint256 _amount, uint256 _duration) external nonReentrant {
        require(_amount > 0, "Cannot lock 0");
        require(_duration >= MIN_LOCK && _duration <= MAX_LOCK, "Invalid lock duration");
        require(locks[msg.sender].amount == 0, "Already locked — extend or unlock first");
        require(loveToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        uint256 unlockAt = block.timestamp + _duration;
        locks[msg.sender] = Lock({
            amount: _amount,
            lockedAt: block.timestamp,
            unlockAt: unlockAt,
            maxLock: _duration
        });

        emit Locked(msg.sender, _amount, unlockAt);
    }

    function unlock() external nonReentrant {
        Lock storage l = locks[msg.sender];
        require(l.amount > 0, "No lock");
        require(block.timestamp >= l.unlockAt, "Lock not expired");

        uint256 amount = l.amount;
        l.amount = 0;
        require(loveToken.transfer(msg.sender, amount), "Transfer failed");

        emit Unlocked(msg.sender, amount);
    }

    function extendLock(uint256 _newDuration) external nonReentrant {
        Lock storage l = locks[msg.sender];
        require(l.amount > 0, "No lock");
        require(_newDuration >= MIN_LOCK && _newDuration <= MAX_LOCK, "Invalid duration");

        // New unlock time must be further in the future
        uint256 newUnlock = block.timestamp + _newDuration;
        require(newUnlock > l.unlockAt, "Can only extend");

        l.maxLock = _newDuration;
        l.unlockAt = newUnlock;

        emit LockExtended(msg.sender, newUnlock);
    }

    // --- Voting power ---

    function getVotingPower(address _user) public view returns (uint256) {
        Lock memory l = locks[_user];
        if (l.amount == 0 || block.timestamp >= l.unlockAt) return 0;

        uint256 remaining = l.unlockAt - block.timestamp;
        // veLOVE = amount * (remaining / maxLock) * (BOOST_NUMERATOR / BOOST_DENOMINATOR)
        return (l.amount * remaining * BOOST_NUMERATOR) / (l.maxLock * BOOST_DENOMINATOR);
    }

    function getRewardBoostBps(address _user) external view returns (uint256) {
        Lock memory l = locks[_user];
        if (l.amount == 0) return 10000; // 1.0x base

        uint256 remaining = l.unlockAt > block.timestamp ? l.unlockAt - block.timestamp : 0;
        uint256 lockRatio = (remaining * 1e18) / l.maxLock;
        uint256 boost = 10000 + (REWARD_BOOST_MAX_BPS - 10000) * lockRatio / 1e18;
        return boost;
    }

    function getLock(address _user) external view returns (uint256 amount, uint256 lockedAt, uint256 unlockAt) {
        Lock memory l = locks[_user];
        return (l.amount, l.lockedAt, l.unlockAt);
    }

    function getTotalLocked() external view returns (uint256) {
        return loveToken.balanceOf(address(this));
    }

    // --- Governance ---

    function createProposal(string calldata _description) external returns (uint256) {
        require(getVotingPower(msg.sender) > 0, "No voting power");
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            description: _description,
            forVotes: 0,
            againstVotes: 0,
            votingDeadline: block.timestamp + VOTING_PERIOD,
            executed: false
        });
        emit ProposalCreated(id, msg.sender, _description);
        return id;
    }

    function vote(uint256 _proposalId, bool _support) external nonReentrant {
        Proposal storage p = proposals[_proposalId];
        require(p.id != 0, "Proposal does not exist");
        require(block.timestamp < p.votingDeadline, "Voting ended");
        require(!hasVoted[_proposalId][msg.sender], "Already voted");
        require(getVotingPower(msg.sender) > 0, "No voting power");

        uint256 weight = getVotingPower(msg.sender);
        hasVoted[_proposalId][msg.sender] = true;

        if (_support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }

        emit Voted(msg.sender, _proposalId, _support, weight);
    }

    function executeProposal(uint256 _proposalId) external onlyOwner {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp >= p.votingDeadline, "Voting not ended");
        require(!p.executed, "Already executed");
        require(p.forVotes > p.againstVotes, "Proposal rejected");

        p.executed = true;
        emit ProposalExecuted(_proposalId);
    }

    function getProposal(uint256 _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }
}
