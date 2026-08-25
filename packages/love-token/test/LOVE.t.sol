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

        // Fund agents
        love.transfer(agent1, 1_000_000 * 1e18);
        love.transfer(agent2, 1_000_000 * 1e18);

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

    function test_CannotRegisterDuplicate() public {
        vm.expectRevert("Already registered");
        registry.registerAgent(agent1, AGENT1_ID);
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

        // 1M LOVE locked for 4 years should give close to 1M veLOVE
        uint256 power = ve.getVotingPower(agent1);
        assertApproxEqAbs(power, lockAmount, lockAmount / 100); // within 1%
    }

    function test_veLOVEShorterLockLessPower() public {
        uint256 lockAmount = 1_000_000 * 1e18;
        vm.startPrank(agent1);
        love.approve(address(ve), lockAmount);
        ve.lock(lockAmount, 365 days); // 1 year = 25% of max
        vm.stopPrank();

        uint256 power = ve.getVotingPower(agent1);
        assertApproxEqAbs(power, lockAmount / 4, lockAmount / 50); // ~25%
    }

    function test_veLOVEBoostBps() public {
        vm.startPrank(agent1);
        love.approve(address(ve), 1_000_000 * 1e18);
        ve.lock(1_000_000 * 1e18, 4 * 365 days);
        vm.stopPrank();

        uint256 boost = ve.getRewardBoostBps(agent1);
        assertEq(boost, 25000); // 2.5x max
    }

    function test_veLOVEGovernanceVote() public {
        // Agent1 locks LOVE for voting power
        vm.startPrank(agent1);
        love.approve(address(ve), 1_000_000 * 1e18);
        ve.lock(1_000_000 * 1e18, 4 * 365 days);
        vm.stopPrank();

        // Create proposal
        vm.prank(agent1);
        uint256 propId = ve.createProposal("Allocate 10M LOVE to agent inference pool");

        // Vote
        vm.prank(agent1);
        ve.vote(propId, true);

        veLOVE.Proposal memory p = ve.getProposal(propId);
        assertGt(p.forVotes, 0);
    }

    // === Epoch emission (simplified) ===

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
}
