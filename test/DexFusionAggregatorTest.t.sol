//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DexFusionAggregator} from "../src/DexFusionAggregator.sol";
import {LiquidityAnalytics} from "../src/LiquidityAnalytics.sol";
import {TestERC20} from "./TestERC20.t.sol";

contract DexFusionAggregatorTest is Test {
    DexFusionAggregator public aggregator;
    TestERC20 public tokenA;
    TestERC20 public tokenB;
    TestERC20 public usdc;

    // Router addresses
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant PANCAKESWAP_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant PANCAKESWAP_V3_ROUTER = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    
    address public owner;
    address public user1;
    address public user2;
    address public feeRecipient;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PLATFORM_FEE = 30; // 0.3%

    // DEX type constants
    uint8 public constant UNISWAP_V2_TYPE = 0;
    uint8 public constant UNISWAP_V3_TYPE = 1;

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address dex,
        uint256 fee
    );

    function setUp() public {
        // Set up accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        feeRecipient = makeAddr("feeRecipient");

        // Deploy aggregator
        aggregator = new DexFusionAggregator(feeRecipient);

        // Deploy test tokens
        tokenA = new TestERC20("Token A", "TKNA", 18, INITIAL_BALANCE);
        tokenB = new TestERC20("Token B", "TKNB", 18, INITIAL_BALANCE);
        usdc = new TestERC20("Test USDC", "USDC", 6, INITIAL_BALANCE / 10**12);

        // Distribute tokens to users
        tokenA.transfer(user1, 10000 * 10**18);
        tokenB.transfer(user1, 10000 * 10**18);
        usdc.transfer(user1, 10000 * 10**6);

        tokenA.transfer(user2, 5000 * 10**18);
        tokenB.transfer(user2, 5000 * 10**18);
        usdc.transfer(user2, 5000 * 10**6);

        // Add DEXs to aggregator with the 4-parameter function
        aggregator.addDex(UNISWAP_V2_ROUTER, "Uniswap V2", 30, UNISWAP_V2_TYPE);
        aggregator.addDex(UNISWAP_V3_ROUTER, "Uniswap V3", 30, UNISWAP_V3_TYPE);
        aggregator.addDex(SUSHISWAP_ROUTER, "SushiSwap", 25, UNISWAP_V2_TYPE);
    }

    function testDeployment() public {
        assertEq(aggregator.platformFee(), PLATFORM_FEE);
        assertEq(aggregator.feeRecipient(), feeRecipient);
        assertEq(aggregator.owner(), owner);
    }

    function testAddDexV2() public {
        address newDex = makeAddr("newDex");
        aggregator.addDex(newDex, "New DEX V2", 25, UNISWAP_V2_TYPE);
        
        (address router, string memory name, bool isActive, uint256 fee, uint8 dexType) = 
            aggregator.supportedDexs(newDex);
        
        assertEq(router, newDex);
        assertEq(name, "New DEX V2");
        assertTrue(isActive);
        assertEq(fee, 25);
        assertEq(dexType, UNISWAP_V2_TYPE);
    }

    function testAddDexV3() public {
        address newDex = makeAddr("newDex");
        aggregator.addDex(newDex, "New DEX V3", 30, UNISWAP_V3_TYPE);
        
        (address router, string memory name, bool isActive, uint256 fee, uint8 dexType) = 
            aggregator.supportedDexs(newDex);
        
        assertEq(router, newDex);
        assertEq(name, "New DEX V3");
        assertTrue(isActive);
        assertEq(fee, 30);
        assertEq(dexType, UNISWAP_V3_TYPE);
    }

    function testAddDexOnlyOwner() public {
        vm.prank(user1);
        // Expect any revert (doesn't check specific error message)
        vm.expectRevert();
        aggregator.addDex(makeAddr("unauthorizedDex"), "Unauthorized", 30, UNISWAP_V2_TYPE);
    }

    function testAddDexInvalidFee() public {
        vm.expectRevert("Fee too high");
        aggregator.addDex(makeAddr("highFeeDex"), "High Fee DEX", 1001, UNISWAP_V2_TYPE); // > 10%
    }

    function testAddDexInvalidType() public {
        vm.expectRevert("Invalid DEX type");
        aggregator.addDex(makeAddr("invalidDex"), "Invalid DEX", 30, 2); // Invalid type
    }
}