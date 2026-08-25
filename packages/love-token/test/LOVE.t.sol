// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/LOVE.sol";
import "../contracts/AgentRegistry.sol";
import "../contracts/PnLOracle.sol";
import "../contracts/veLOVE.sol";

contract LOVETokenTest is Test {
    LOVE love;
    AgentRegistry registry;
    PnLOracle oracle;
    veLOVE ve;

    address deployer = address(this);
    address team = address(0x1);
    address treasury = address(0x2);
    address liquidity = address(0x3);
    address community = address(0x4);
    address partnership = address(0x5);
    address agent1 = address(0x10);
    address agent2 = address(0x11);
    address orchestrator = address(0x20);

    bytes32 AGENT1_ID = keccak256("sak:agent:001");
    bytes32 AGENT2_ID = keccak256("sak:agent:002");

    function setUp() public {
        love = new LOVE(team, treasury, liquidity, community, partnership);
        registry = new AgentRegistry(address(love));
        oracle = new PnLOracle(address(love), address(registry), orchestrator);

        love.setAgentRegistry(address(registry));
        love.setPnLOracle(address(oracle));
        ve = new veLOVE(address(love));
        love.setVeLOVE(address(ve));

        // Fund agents from community wallet
        vm.startPrank(community);
        love.transfer(agent1, 1_000_000 * 1e18);
        love.transfer(agent2, 1_000_000 * 1e18);
        vm.stopPrank();

        // Register agents
        registry.registerAgent(agent1, AGENT1_ID);
        registry.registerAgent(agent2, AGENT2_ID);
    }

    // === Token allocation ===

    function test_TotalSupply() public {
        assertEq(love.totalSupply(), 1_000_000_000 * 1e18);
    }

    function test_TeamAllocation() public {
        assertEq(love.balanceOf(team), 150_000_000 * 1e18);
    }

    function test_TreasuryAllocation() public {
        assertEq(love.balanceOf(treasury), 200_000_000 * 1e18);
    }

    function test_RewardPoolInContract() public {
        assertEq(love.balanceOf(address(love)), 400_000_000 * 1e18);
    }

    function test_AllAllocationsSumToTotal() public {
        // Community transferred 2M to agents, so include those
        uint256 sum = love.balanceOf(team)
            + love.balanceOf(treasury)
            + love.balanceOf(liquidity)
            + love.balanceOf(community)
            + love.balanceOf(partnership)
            + love.balanceOf(address(love))
            + love.balanceOf(agent1)
            + love.balanceOf(agent2);
        assertEq(sum, 1_000_000_000 * 1e18);
    }

    // === Staking ===

    function test_Stake() public {
        uint256 stakeAmount = 100_000 * 1e18;
        vm.startPrank(agent1);
        love.stake(stakeAmount, 30 days);
        vm.stopPrank();

        (uint256 staked, ) = love.getStake(agent1);
        assertEq(staked, stakeAmount);
        assertEq(love.totalStaked(), stakeAmount);
    }

    function test_UnstakeAfterLock() public {
        uint256 stakeAmount = 100_000 * 1e18;
        vm.startPrank(agent1);
        love.stake(stakeAmount, 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 balanceBefore = love.balanceOf(agent1);
        vm.startPrank(agent1);
        love.unstake();
        vm.stopPrank();

        assertEq(love.balanceOf(agent1), balanceBefore + stakeAmount);
        assertEq(love.totalStaked(), 0);
    }

    function test_CannotUnstakeBeforeLock() public {
        vm.startPrank(agent1);
        love.stake(100_000 * 1e18, 365 days);
        vm.stopPrank();

        vm.expectRevert("Stake still locked");
        vm.prank(agent1);
        love.unstake();
    }

    function test_CannotStakeZero() public {
        vm.expectRevert("Cannot stake 0");
        vm.prank(agent1);
        love.stake(0, 30 days);
    }

    // === Agent Registry ===

    function test_RegisterAgent() public {
        assertTrue(registry.isRegisteredAgent(agent1));
        assertEq(registry.getAgentCount(), 2);
    }

    function test_AgentReputation() public {
        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.reputation, 500);
        assertTrue(a.active);
    }

    function test_UpdateReputation() public {
        registry.updateReputation(agent1, 100, true);
        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.reputation, 600);
    }

    function test_ReputationCapsAt1000() public {
        registry.updateReputation(agent1, 600, true);
        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.reputation, 1000);
    }

    function test_CannotRegisterDuplicate() public {
        vm.expectRevert("Already registered");
        registry.registerAgent(agent1, AGENT1_ID);
    }

    function test_CannotRegisterDuplicateAgentId() public {
        address agent3 = address(0x12);
        vm.expectRevert("Agent ID taken");
        registry.registerAgent(agent3, AGENT1_ID);
    }

    function test_DeactivateAgent() public {
        registry.deactivateAgent(agent1);
        assertFalse(registry.isRegisteredAgent(agent1));
    }

    function test_GetActiveAgents() public {
        registry.deactivateAgent(agent2);
        address[] memory active = registry.getActiveAgents();
        assertEq(active.length, 1);
        assertEq(active[0], agent1);
    }

    // === veLOVE governance ===

    function test_veLOVELock() public {
        uint256 lockAmount = 500_000 * 1e18;
        vm.startPrank(agent1);
        love.approve(address(ve), lockAmount);
        ve.lock(lockAmount, 365 days);
        vm.stopPrank();

        (uint256 amount, , ) = ve.getLock(agent1);
        assertEq(amount, lockAmount);
    }

    function test_veLOVEVotingPower() public {
        uint256 lockAmount = 1_000_000 * 1e18;
        vm.startPrank(agent1);
        love.approve(address(ve), lockAmount);
        ve.lock(lockAmount, 4 * 365 days);
        vm.stopPrank();

        uint256 power = ve.getVotingPower(agent1);
        assertApproxEqAbs(power, lockAmount, lockAmount / 100);
    }

    function test_veLOVEVotingPowerDecays() public {
        uint256 lockAmount = 1_000_000 * 1e18;
        vm.startPrank(agent1);
        love.approve(address(ve), lockAmount);
        ve.lock(lockAmount, 365 days);
        vm.stopPrank();

        // At lock time, voting power == full amount
        uint256 powerAtStart = ve.getVotingPower(agent1);
        assertApproxEqAbs(powerAtStart, lockAmount, lockAmount / 100);

        // After 75% of lock elapsed, power should be ~25%
        vm.warp(block.timestamp + 274 days); // 75% of 365
        uint256 powerAt75 = ve.getVotingPower(agent1);
        assertApproxEqAbs(powerAt75, lockAmount / 4, lockAmount / 20);
    }

    function test_veLOVEBoostBps() public {
        vm.startPrank(agent1);
        love.approve(address(ve), 1_000_000 * 1e18);
        ve.lock(1_000_000 * 1e18, 4 * 365 days);
        vm.stopPrank();

        uint256 boost = ve.getRewardBoostBps(agent1);
        assertEq(boost, 25000);
    }

    function test_veLOVENoLockBaseBoost() public {
        uint256 boost = ve.getRewardBoostBps(agent2);
        assertEq(boost, 10000); // 1.0x base
    }

    function test_veLOVEGovernanceVote() public {
        vm.startPrank(agent1);
        love.approve(address(ve), 1_000_000 * 1e18);
        ve.lock(1_000_000 * 1e18, 4 * 365 days);
        vm.stopPrank();

        vm.prank(agent1);
        uint256 propId = ve.createProposal("Allocate 10M LOVE to agent inference pool");

        vm.prank(agent1);
        ve.vote(propId, true);

        veLOVE.Proposal memory p = ve.getProposal(propId);
        assertGt(p.forVotes, 0);
    }

    function test_veLOVECannotVoteWithoutLock() public {
        vm.expectRevert("No voting power");
        vm.prank(agent2);
        ve.createProposal("test");
    }

    function test_veLOVEUnlockAfterExpiry() public {
        uint256 lockAmount = 500_000 * 1e18;
        vm.startPrank(agent1);
        love.approve(address(ve), lockAmount);
        ve.lock(lockAmount, 7 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(agent1);
        ve.unlock();
        assertEq(love.balanceOf(agent1), 1_000_000 * 1e18);
    }

    // === Epoch emission ===

    function test_EpochNotCommittedInitially() public {
        (, , bool committed) = love.epochs(0);
        assertFalse(committed);
    }

    function test_RemainingRewardPool() public {
        assertEq(love.getRemainingRewardPool(), 400_000_000 * 1e18);
    }

    function test_Burn() public {
        uint256 before = love.totalSupply();
        vm.startPrank(agent1);
        love.burn(100_000 * 1e18);
        vm.stopPrank();
        assertEq(love.totalSupply(), before - 100_000 * 1e18);
    }

    function test_StakeDoesNotAffectRewardPool() public {
        // Staking from agent wallet adds LOVE to contract but also increases totalStaked
        // So reward pool (balanceOf - totalStaked) stays the same
        uint256 poolBefore = love.getRemainingRewardPool();
        vm.startPrank(agent1);
        love.stake(100_000 * 1e18, 30 days);
        vm.stopPrank();
        assertEq(love.getRemainingRewardPool(), poolBefore);
    }
}
