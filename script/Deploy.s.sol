// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BoltToken.sol";

/**
 * ⚡ $BOLT Deployment Script
 *
 * Testnet
 * ───────
 *   make deploy-testnet
 *
 * Mainnet
 * ───────
 *   make deploy-mainnet
 *
 * Required .env variables
 * ───────────────────────
 *   PRIVATE_KEY
 *   MARKETING_WALLET
 *   LIQUIDITY_WALLET
 *   RESERVE_WALLET
 *   PANCAKE_ROUTER        (set to testnet or mainnet address)
 *   BSCSCAN_API_KEY       (for auto-verify)
 */
contract DeployBolt is Script {

    function run() external {
        // ── Load env ─────────────────────────────────────────────────────────
        uint256 deployerKey     = vm.envUint("PRIVATE_KEY");
        address marketingWallet = vm.envAddress("MARKETING_WALLET");
        address liquidityWallet = vm.envAddress("LIQUIDITY_WALLET");
        address reserveWallet   = vm.envAddress("RESERVE_WALLET");
        address pancakeRouter   = vm.envAddress("PANCAKE_ROUTER");

        address deployer = vm.addr(deployerKey);

        // ── Pre-flight checks ─────────────────────────────────────────────────
        require(marketingWallet != address(0), "Deploy: zero marketing wallet");
        require(liquidityWallet != address(0), "Deploy: zero liquidity wallet");
        require(reserveWallet   != address(0), "Deploy: zero reserve wallet");
        require(pancakeRouter   != address(0), "Deploy: zero router address");

        console.log("=================================================");
        console.log("  $BOLT Deployment");
        console.log("=================================================");
        console.log("  Deployer        :", deployer);
        console.log("  Marketing Wallet:", marketingWallet);
        console.log("  Liquidity Wallet:", liquidityWallet);
        console.log("  Reserve Wallet  :", reserveWallet);
        console.log("  PancakeRouter   :", pancakeRouter);
        console.log("-------------------------------------------------");

        // ── Deploy ────────────────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        BinanceLightningBolt bolt = new BinanceLightningBolt(
            marketingWallet,
            liquidityWallet,
            reserveWallet,
            pancakeRouter
        );

        vm.stopBroadcast();

        // ── Post-deploy info ──────────────────────────────────────────────────
        console.log("=================================================");
        console.log("  DEPLOYMENT SUCCESSFUL");
        console.log("=================================================");
        console.log("  Contract Address:", address(bolt));
        console.log("  Token Name      :", bolt.name());
        console.log("  Token Symbol    :", bolt.symbol());
        console.log("  Total Supply    :", bolt.totalSupply() / 1e18, "BOLT");
        console.log("  PancakePair     :", bolt.pancakePair());
        console.log("  Owner           :", bolt.owner());
        console.log("-------------------------------------------------");
        console.log("  NEXT STEPS:");
        console.log("  1. startPresale() with your chosen params");
        console.log("  2. Wait for presale to end / hard cap");
        console.log("  3. finalizePresale() to add liquidity + enable trading");
        console.log("  4. Lock LP tokens on PinkLock / Team.Finance");
        console.log("=================================================");
    }
}
