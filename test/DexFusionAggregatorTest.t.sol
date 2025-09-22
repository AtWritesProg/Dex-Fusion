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

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
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
        usdc = new TestERC20("Test USDC", "USDC", 6, INITIAL_BALANCE / 10 ** 12);

        // Distribute tokens to users
        tokenA.transfer(user1, 10000 * 10 ** 18);
        tokenB.transfer(user1, 10000 * 10 ** 18);
        usdc.transfer(user1, 10000 * 10 ** 6);

        tokenA.transfer(user2, 5000 * 10 ** 18);
        tokenB.transfer(user2, 5000 * 10 ** 18);
        usdc.transfer(user2, 5000 * 10 ** 6);

        // Add DEXs to aggregator with the 4-parameter function
        aggregator.addDex(UNISWAP_V2_ROUTER, "Uniswap V2", 30, UNISWAP_V2_TYPE);
        aggregator.addDex(UNISWAP_V3_ROUTER, "Uniswap V3", 30, UNISWAP_V3_TYPE);
        aggregator.addDex(SUSHISWAP_ROUTER, "SushiSwap", 25, UNISWAP_V2_TYPE);
    }

    function testDeployment() public view {
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

    function testGetQuoteFromDex() public {
        // Mock the getAmountsOut call for V2 router
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10 ** 18;
        amounts[1] = 1800 * 10 ** 18;

        vm.mockCall(
            UNISWAP_V2_ROUTER,
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", 1000 * 10 ** 18, path),
            abi.encode(amounts)
        );

        uint256 quote = aggregator.getQuoteFromDex(address(tokenA), address(tokenB), 1000 * 10 ** 18, UNISWAP_V2_ROUTER);

        assertEq(quote, 1800 * 10 ** 18);
    }

    function testGetQuoteFromV3Dex() public view {
        // V3 quotes should return 0 for now (not implemented)
        uint256 quote = aggregator.getQuoteFromDex(address(tokenA), address(tokenB), 1000 * 10 ** 18, UNISWAP_V3_ROUTER);

        assertEq(quote, 0);
    }

    function testFindBestRoute() public {
        // Mock Uniswap V2 quote
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory uniAmounts = new uint256[](2);
        uniAmounts[0] = 1000 * 10 ** 18;
        uniAmounts[1] = 1800 * 10 ** 18;

        vm.mockCall(
            UNISWAP_V2_ROUTER,
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", 1000 * 10 ** 18, path),
            abi.encode(uniAmounts)
        );

        // Mock SushiSwap quote (better rate)
        uint256[] memory sushiAmounts = new uint256[](2);
        sushiAmounts[0] = 1000 * 10 ** 18;
        sushiAmounts[1] = 1850 * 10 ** 18; // Better rate

        vm.mockCall(
            SUSHISWAP_ROUTER,
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", 1000 * 10 ** 18, path),
            abi.encode(sushiAmounts)
        );

        // Find best route
        (address bestDex, uint256 bestAmount) =
            aggregator.findBestRoute(address(tokenA), address(tokenB), 1000 * 10 ** 18);

        assertEq(bestDex, SUSHISWAP_ROUTER);
        assertEq(bestAmount, 1850 * 10 ** 18);
    }

    function testGetAllQuotes() public {
        // Mock quotes for all DEXs
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Mock Uniswap V2
        uint256[] memory uniAmounts = new uint256[](2);
        uniAmounts[0] = 1000 * 10 ** 18;
        uniAmounts[1] = 1800 * 10 ** 18;

        vm.mockCall(
            UNISWAP_V2_ROUTER,
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", 1000 * 10 ** 18, path),
            abi.encode(uniAmounts)
        );

        // Mock SushiSwap
        uint256[] memory sushiAmounts = new uint256[](2);
        sushiAmounts[0] = 1000 * 10 ** 18;
        sushiAmounts[1] = 1850 * 10 ** 18;

        vm.mockCall(
            SUSHISWAP_ROUTER,
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", 1000 * 10 ** 18, path),
            abi.encode(sushiAmounts)
        );

        DexFusionAggregator.RouteQuote[] memory quotes =
            aggregator.getAllQuotes(address(tokenA), address(tokenB), 1000 * 10 ** 18);

        // Should have quotes from V2 DEXs (V3 returns 0 so might be filtered)
        assertGe(quotes.length, 2);

        // Check that we got quotes
        bool foundUniswap = false;
        bool foundSushi = false;

        for (uint256 i = 0; i < quotes.length; i++) {
            if (quotes[i].dexRouter == UNISWAP_V2_ROUTER) {
                foundUniswap = true;
                assertEq(quotes[i].amountOut, 1800 * 10 ** 18);
            }
            if (quotes[i].dexRouter == SUSHISWAP_ROUTER) {
                foundSushi = true;
                assertEq(quotes[i].amountOut, 1850 * 10 ** 18);
            }
        }

        assertTrue(foundUniswap);
        assertTrue(foundSushi);
    }

    function testUpdatePlatformFee() public {
        uint256 newFee = 50; // 0.5%
        aggregator.updatePlatformFee(newFee);
        assertEq(aggregator.platformFee(), newFee);
    }

    function testUpdatePlatformFeeOnlyOwner() public {
        vm.prank(user1);
        // Expect any revert (doesn't check specific error message)
        vm.expectRevert();
        aggregator.updatePlatformFee(50);
    }

    function testUpdatePlatformFeeInvalidFee() public {
        vm.expectRevert("Fee too high");
        aggregator.updatePlatformFee(1001); // > 10%
    }

    function testToggleDexStatus() public {
        // Initially active
        (,, bool isActive,,) = aggregator.supportedDexs(UNISWAP_V2_ROUTER);
        assertTrue(isActive);

        // Toggle to inactive
        aggregator.toggleDexStatus(UNISWAP_V2_ROUTER);
        (,, isActive,,) = aggregator.supportedDexs(UNISWAP_V2_ROUTER);
        assertFalse(isActive);

        // Toggle back to active
        aggregator.toggleDexStatus(UNISWAP_V2_ROUTER);
        (,, isActive,,) = aggregator.supportedDexs(UNISWAP_V2_ROUTER);
        assertTrue(isActive);
    }

    function testUpdateFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        aggregator.updateFeeRecipient(newRecipient);
        assertEq(aggregator.feeRecipient(), newRecipient);
    }

    function testUpdateFeeRecipientInvalidAddress() public {
        vm.expectRevert("Invalid recipient");
        aggregator.updateFeeRecipient(address(0));
    }

    function testEmergencyWithdraw() public {
        // Send some tokens to the contract
        tokenA.transfer(address(aggregator), 1000 * 10 ** 18);

        uint256 contractBalance = tokenA.balanceOf(address(aggregator));
        uint256 ownerBalanceBefore = tokenA.balanceOf(owner);

        aggregator.emergencyWithdraw(address(tokenA), contractBalance);

        assertEq(tokenA.balanceOf(address(aggregator)), 0);
        assertEq(tokenA.balanceOf(owner), ownerBalanceBefore + contractBalance);
    }

    function testGetTotalDexs() public view {
        assertEq(aggregator.getTotalDexs(), 3); // We added 3 DEXs in setUp
    }

    function testGetActiveDexs() public {
        address[] memory activeDexs = aggregator.getActiveDexs();
        assertEq(activeDexs.length, 3);

        // Toggle one DEX off
        aggregator.toggleDexStatus(UNISWAP_V2_ROUTER);
        activeDexs = aggregator.getActiveDexs();
        assertEq(activeDexs.length, 2);
    }

    // Swap execution tests
    function testSwapWithZeroAmount() public {
        DexFusionAggregator.SwapParams memory params = DexFusionAggregator.SwapParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            amountIn: 0,
            amountOutMin: 0,
            dexRouter: UNISWAP_V2_ROUTER,
            swapData: "",
            deadline: block.timestamp + 3600,
            poolFee: 3000
        });

        vm.prank(user1);
        vm.expectRevert("Invalid amount");
        aggregator.executeSwap(params);
    }

    function testSwapWithExpiredDeadline() public {
        DexFusionAggregator.SwapParams memory params = DexFusionAggregator.SwapParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            amountIn: 1000 * 10 ** 18,
            amountOutMin: 1700 * 10 ** 18,
            dexRouter: UNISWAP_V2_ROUTER,
            swapData: "",
            deadline: block.timestamp - 1, // Expired
            poolFee: 3000
        });

        vm.prank(user1);
        vm.expectRevert("Swap expired");
        aggregator.executeSwap(params);
    }

    function testSwapWithUnsupportedDex() public {
        address unsupportedDex = makeAddr("unsupportedDex");

        DexFusionAggregator.SwapParams memory params = DexFusionAggregator.SwapParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            amountIn: 1000 * 10 ** 18,
            amountOutMin: 1700 * 10 ** 18,
            dexRouter: unsupportedDex,
            swapData: "",
            deadline: block.timestamp + 3600,
            poolFee: 3000
        });

        vm.prank(user1);
        vm.expectRevert("DEX not supported");
        aggregator.executeSwap(params);
    }

    // Fuzz Tests
    function testFuzzSwapAmounts(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 * 10 ** 15, 1000 * 10 ** 18); // 0.001 to 1000 tokens

        uint256 expectedOutput = (amountIn * 80) / 100;

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = expectedOutput;

        vm.mockCall(
            UNISWAP_V2_ROUTER,
            abi.encodeWithSignature("getAmountsOut(uint256,address[])", amountIn, path),
            abi.encode(amounts)
        );

        uint256 quote = aggregator.getQuoteFromDex(address(tokenA), address(tokenB), amountIn, UNISWAP_V2_ROUTER);

        assertEq(quote, expectedOutput);
    }

    function testFuzzPlatformFee(uint256 fee) public {
        fee = bound(fee, 0, 1000); // 0% to 10%

        aggregator.updatePlatformFee(fee);
        assertEq(aggregator.platformFee(), fee);
    }

    // Helper Functions
    function _mockSuccessfulSwap(address router, uint256 amountIn, uint256 amountOut) internal {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        vm.mockCall(
            router, abi.encodeWithSignature("getAmountsOut(uint256,address[])", amountIn, path), abi.encode(amounts)
        );

        vm.mockCall(
            router,
            abi.encodeWithSignature("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"),
            abi.encode(amounts)
        );
    }

    receive() external payable {}
}
