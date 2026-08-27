// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LOVE} from "../contracts/LOVE.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {PnLOracle} from "../contracts/PnLOracle.sol";
import {veLOVE} from "../contracts/veLOVE.sol";

contract Deploy is Script {
    // Testnet allocation wallets (generated fresh for Base Sepolia)
    address constant TEAM_WALLET = 0xEaBdd065Ab14a48029EbB1d44BcF254E5C69709D;
    address constant TREASURY_WALLET = 0x1Ff6FEb309f7d19B5b891243c14E3c8Ed4E97b92;
    address constant LIQUIDITY_WALLET = 0xc3488CA4E5ddaFc1F9EbaCA56F9C8790753220E0;
    address constant COMMUNITY_WALLET = 0x3599b583617F2B9Ca480383701E226a60d7e3379;
    address constant PARTNERSHIP_WALLET = 0x31BFe544fd0C804378270e3C28e85F1Dd7bc6614;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy LOVE token
        LOVE love = new LOVE(
            TEAM_WALLET,
            TREASURY_WALLET,
            LIQUIDITY_WALLET,
            COMMUNITY_WALLET,
            PARTNERSHIP_WALLET
        );
        console.log("LOVE token deployed at:", address(love));

        // 2. Deploy AgentRegistry
        AgentRegistry registry = new AgentRegistry(address(love));
        console.log("AgentRegistry deployed at:", address(registry));

        // 3. Deploy PnLOracle
        PnLOracle oracle = new PnLOracle(address(love), address(registry), deployer);
        console.log("PnLOracle deployed at:", address(oracle));

        // 4. Deploy veLOVE
        veLOVE ve = new veLOVE(address(love));
        console.log("veLOVE deployed at:", address(ve));

        vm.stopBroadcast();

        console.log("=== Deployment Summary ===");
        console.log("LOVE:", address(love));
        console.log("AgentRegistry:", address(registry));
        console.log("PnLOracle:", address(oracle));
        console.log("veLOVE:", address(ve));
    }
}
