//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DexFusionAggregator} from "../src/DexFusionAggregator.sol";
import {LiquidityAnalytics} from "../src/LiquidityAnalytics.sol";
import {TestERC20} from "../test/TestERC20.t.sol";

contract DeployDexFusionAggregator is Script {
    function run() external {
        // Get deployer address from the wallet
        address deployer = msg.sender;

        console.log("Deploying to Sepolia...");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        require(deployer.balance > 0.05 ether, "Insufficient balance for deployment");

        vm.startBroadcast();

        // Deploy LiquidityAnalytics
        console.log("Deploying LiquidityAnalytics...");
        LiquidityAnalytics analytics = new LiquidityAnalytics();
        console.log("LiquidityAnalytics deployed:", address(analytics));

        // Deploy DexFusionAggregator
        console.log("Deploying DexFusionAggregator...");
        DexFusionAggregator aggregator = new DexFusionAggregator(deployer);
        console.log("DexFusionAggregator deployed:", address(aggregator));

        // Deploy test tokens for Sepolia testing
        console.log("Deploying test tokens...");
        TestERC20 usdc = new TestERC20("Test USDC", "USDC", 6, 1000000 * 10 ** 6);
        TestERC20 weth = new TestERC20("Test WETH", "WETH", 18, 10000 * 10 ** 18);
        TestERC20 dai = new TestERC20("Test DAI", "DAI", 18, 1000000 * 10 ** 18);

        console.log("Test USDC:", address(usdc));
        console.log("Test WETH:", address(weth));
        console.log("Test DAI:", address(dai));

        // Add DEXs (Sepolia uses same router addresses as mainnet)
        console.log("Adding DEX routers...");
        aggregator.addDex(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2
            "Uniswap V2",
            30, // 0.3%
            0 // V2 type
        );

        aggregator.addDex(
            0xE592427A0AEce92De3Edee1F18E0157C05861564, // Uniswap V3
            "Uniswap V3",
            30, // 0.3%
            1 // V3 type
        );

        // Configure analytics
        console.log("Configuring analytics...");
        analytics.setAuthorizedUpdater(address(aggregator), true);

        // Mint test tokens to deployer
        console.log("Minting test tokens...");
        usdc.mint(deployer, 50000 * 10 ** 6); // 50k USDC
        weth.mint(deployer, 100 * 10 ** 18); // 100 WETH
        dai.mint(deployer, 100000 * 10 ** 18); // 100k DAI

        vm.stopBroadcast();

        // Create deployment info JSON
        string memory deploymentInfo = string(
            abi.encodePacked(
                "{\n",
                '  "network": "sepolia",\n',
                '  "chainId": 11155111,\n',
                '  "timestamp": "',
                vm.toString(block.timestamp),
                '",\n',
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "contracts": {\n',
                '    "DexFusionAggregator": "',
                vm.toString(address(aggregator)),
                '",\n',
                '    "LiquidityAnalytics": "',
                vm.toString(address(analytics)),
                '"\n',
                "  },\n",
                '  "testTokens": {\n',
                '    "USDC": "',
                vm.toString(address(usdc)),
                '",\n',
                '    "WETH": "',
                vm.toString(address(weth)),
                '",\n',
                '    "DAI": "',
                vm.toString(address(dai)),
                '"\n',
                "  },\n",
                '  "configuration": {\n',
                '    "platformFee": "0.3%",\n',
                '    "feeRecipient": "',
                vm.toString(deployer),
                '"\n',
                "  }\n",
                "}"
            )
        );

        vm.writeFile("deployments/sepolia-deployment.json", deploymentInfo);

        console.log("\n=== Deployment Summary ===");
        console.log("Network: Sepolia (11155111)");
        console.log("DexFusionAggregator:", address(aggregator));
        console.log("LiquidityAnalytics:", address(analytics));
        console.log("Test USDC:", address(usdc));
        console.log("Test WETH:", address(weth));
        console.log("Test DAI:", address(dai));
        console.log("Deployer:", deployer);
        console.log("Gas used: Check transaction receipt");
        console.log("Deployment file: deployments/sepolia-deployment.json");
    }
}
