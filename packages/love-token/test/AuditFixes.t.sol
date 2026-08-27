// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/LOVE.sol";
import "../contracts/AgentRegistry.sol";
import "../contracts/PnLOracle.sol";
import "../contracts/interfaces/IPnLOracle.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title Audit Fixes Test Suite
 * @notice Tests for the 3 high-severity + 4 medium findings from Audit v1.0
 */
contract AuditFixesTest is Test {
    LOVE public love;
    AgentRegistry public registry;
    PnLOracle public oracle;
    TimelockController public timelock;

    address owner = address(this);
    address team = address(0x1);
    address treasury = address(0x2);
    address liquidity = address(0x3);
    address community = address(0x4);
    address partnership = address(0x5);
    address agent1 = address(0x10);
    address agent2 = address(0x11);

    // Orchestrator with known private key for signing
    uint256 orchestratorPk = 42;
    address orchestrator;

    function setUp() public {
        orchestrator = vm.addr(orchestratorPk);

        love = new LOVE(team, treasury, liquidity, community, partnership);
        registry = new AgentRegistry(address(love));
        oracle = new PnLOracle(address(love), address(registry), orchestrator);

        love.setAgentRegistry(address(registry));
        love.setPnLOracle(address(oracle));

        // Setup timelock
        address[] memory proposers = new address[](1);
        proposers[0] = owner;
        address[] memory executors = new address[](1);
        executors[0] = owner;
        timelock = new TimelockController(1 hours, proposers, executors, owner);
        love.setTimelock(address(timelock));

        // Register agents
        registry.registerAgent(agent1, keccak256("sak:agent:001"));
        registry.registerAgent(agent2, keccak256("sak:agent:002"));

        // Give agents tokens from team allocation
        vm.startPrank(team);
        love.transfer(agent1, 1_000_000 * 1e18);
        love.transfer(agent2, 1_000_000 * 1e18);
        vm.stopPrank();
    }

    // --- H-1: slashBps cannot exceed 50% ---

    function testH01_CannotSetSlashBpsAbove50Percent() public {
        vm.expectRevert("Slash rate cannot exceed 50%");
        vm.prank(address(timelock));
        love.setSlashBps(5001);
    }

    function testH01_CanSetSlashBpsAt50Percent() public {
        vm.prank(address(timelock));
        love.setSlashBps(5000);
        assertEq(love.slashBps(), 5000);
    }

    function testH01_DefaultSlashBpsIs25Percent() public {
        assertEq(love.slashBps(), 2500);
    }

    // --- H-3: Admin functions require timelock ---

    function testH03_OwnerCannotDirectlyCallSetAgentRegistry() public {
        vm.expectRevert("Only timelock");
        love.setAgentRegistry(address(0x99));
    }

    function testH03_OwnerCannotDirectlySetSlashBps() public {
        vm.expectRevert("Only timelock");
        love.setSlashBps(3000);
    }

    function testH03_TimelockCanCallSetAgentRegistry() public {
        vm.prank(address(timelock));
        love.setAgentRegistry(address(0x99));
        assertEq(address(love.agentRegistry()), address(0x99));
    }

    // --- M-2: Treasury address is dedicated ---

    function testM02_TreasuryAddressIsSet() public {
        assertEq(love.treasuryAddress(), treasury);
    }

    function testM02_SlashSendsToTreasuryNotOwner() public {
        vm.startPrank(agent1);
        love.stake(100_000 * 1e18, 7 days);
        vm.stopPrank();

        uint256 treasuryBefore = love.balanceOf(treasury);
        uint256 ownerBefore = love.balanceOf(owner);

        registry.slashAgent(agent1, "test violation");

        uint256 treasuryAfter = love.balanceOf(treasury);
        uint256 ownerAfter = love.balanceOf(owner);

        assertGt(treasuryAfter, treasuryBefore);
        assertEq(ownerAfter, ownerBefore);
    }

    // --- M-3: getRemainingRewardPool underflow guard ---

    function testM03_RemainingRewardPoolDoesNotRevert() public {
        // Send tokens directly to contract (bypasses normal accounting)
        vm.prank(team);
        love.transfer(address(love), 100 * 1e18);
        uint256 remaining = love.getRemainingRewardPool();
        assertGt(remaining, 0);
    }

    // --- M-4: advanceEpoch requires committed epoch ---

    function testM04_CannotAdvanceUncommittedEpoch() public {
        vm.warp(block.timestamp + 8 days);
        vm.prank(address(timelock));
        vm.expectRevert("Current epoch must be committed before advancing");
        love.advanceEpoch();
    }

    // --- H-2: Challenge period on PnLOracle ---

    function testH02_ChallengeBlocksCommit() public {
        IPnLOracle.PnLReport memory report = _makeReport(agent1, 1000 * 1e18, 10, 50_000);
        oracle.reportPnL(report);

        oracle.proposeEpoch();
        oracle.challengeRoot(0, "Missing agent report");

        vm.expectRevert("Root was challenged");
        oracle.commitEpochRoot(0);
    }

    function testH02_CannotCommitBeforeChallengePeriod() public {
        IPnLOracle.PnLReport memory report = _makeReport(agent1, 1000 * 1e18, 10, 50_000);
        oracle.reportPnL(report);
        oracle.proposeEpoch();

        vm.expectRevert("Challenge period not over");
        oracle.commitEpochRoot(0);
    }

    function testH02_CanCommitAfterChallengePeriod() public {
        IPnLOracle.PnLReport memory report = _makeReport(agent1, 1000 * 1e18, 10, 50_000);
        oracle.reportPnL(report);
        oracle.proposeEpoch();

        vm.warp(block.timestamp + 25 hours);
        oracle.commitEpochRoot(0);

        (bytes32 root, uint256 allocated, bool committed) = love.epochs(0);
        assertTrue(committed);
        assertGt(allocated, 0);
    }

    // --- M-1: Incremental stake uses max lock ---

    function testM01_IncrementalStakeUsesMaxLock() public {
        vm.startPrank(agent1);
        love.stake(100_000 * 1e18, 7 days);
        (, uint256 lock1) = love.getStake(agent1);

        love.stake(50_000 * 1e18, 3 days);
        (uint256 amount, uint256 lock2) = love.getStake(agent1);

        assertEq(lock2, lock1);
        assertEq(amount, 150_000 * 1e18);
        vm.stopPrank();
    }

    // --- Helper ---

    function _makeReport(address agent, int256 pnl, uint256 tasks, uint256 gas) internal returns (IPnLOracle.PnLReport memory) {
        uint256 ts = block.timestamp;
        bytes32 messageHash = keccak256(abi.encodePacked(agent, pnl, tasks, gas, ts));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(orchestratorPk, ethSignedHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        return IPnLOracle.PnLReport({
            agent: agent,
            pnl: pnl,
            tasksCompleted: tasks,
            gasConsumed: gas,
            timestamp: ts,
            signature: sig
        });
    }
}
