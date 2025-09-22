//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LiquidityAnalytics} from "../src/LiquidityAnalytics.sol";
import {TestERC20} from "./TestERC20.t.sol";

contract LiquidityAnalyticsTest is Test {
    LiquidityAnalytics public analytics;
    TestERC20 public tokenA;
    TestERC20 public tokenB;
    TestERC20 public tokenC;

    address public owner;
    address public user1;
    address public user2;
    address public authorizedUpdater;
    address public dexRouter;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;

    event PoolDataUpdated(
        address indexed pool, address indexed dex, uint256 liquidity, uint256 volume24h, uint256 timestamp
    );

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    function setUp() public {
        // Set up accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        authorizedUpdater = makeAddr("authorizedUpdater");
        dexRouter = makeAddr("dexRouter");

        // Deploy analytics contract
        analytics = new LiquidityAnalytics();

        // Deploy test tokens
        tokenA = new TestERC20("Token A", "TKNA", 18, INITIAL_BALANCE);
        tokenB = new TestERC20("Token B", "TKNB", 18, INITIAL_BALANCE);
        tokenC = new TestERC20("Token C", "TKNC", 6, INITIAL_BALANCE / 10 ** 12);

        // Set up authorized updater
        analytics.setAuthorizedUpdater(authorizedUpdater, true);
    }

    function testDeployment() public view {
        assertEq(analytics.owner(), owner);
        assertTrue(analytics.authorizedUpdaters(owner));
        assertEq(analytics.getTotalPools(), 0);
        assertEq(analytics.getTotalTrackedTokens(), 0);
        assertEq(analytics.SNAPSHOT_INTERVAL(), 1 hours);
        assertEq(analytics.MAX_SNAPSHOTS(), 168);
    }

    function testSetAuthorizedUpdater() public {
        assertFalse(analytics.authorizedUpdaters(user1));

        analytics.setAuthorizedUpdater(user1, true);
        assertTrue(analytics.authorizedUpdaters(user1));

        analytics.setAuthorizedUpdater(user1, false);
        assertFalse(analytics.authorizedUpdaters(user1));
    }

    function testSetAuthorizedUpdaterOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        analytics.setAuthorizedUpdater(user2, true);
    }

    function testUpdatePoolData() public {
        address poolAddress = makeAddr("TestPool");
        uint256 liquidity = 1000000 * 10 ** 18;
        uint256 volume24h = 50000 * 10 ** 18;
        uint256 fees24h = 500 * 10 ** 18;
        uint256 apr = 1200;

        vm.expectEmit(true, true, false, true);
        emit PoolDataUpdated(poolAddress, dexRouter, liquidity, volume24h, block.timestamp);

        analytics.updatePoolData(
            poolAddress, address(tokenA), address(tokenB), dexRouter, "Uniswap V2", liquidity, volume24h, fees24h, apr
        );

        (
            address pool,
            address token0,
            address token1,
            address router,
            string memory dexName,
            uint256 storedLiquidity,
            uint256 storedVolume,
            uint256 storedFees,
            uint256 storedApr,
            uint256 lastUpdated,
            bool isActive
        ) = analytics.pools(poolAddress);

        assertEq(pool, poolAddress);
        assertEq(token0, address(tokenA));
        assertEq(token1, address(tokenB));
        assertEq(router, dexRouter);
        assertEq(dexName, "Uniswap V2");
        assertEq(storedLiquidity, liquidity);
        assertEq(storedVolume, volume24h);
        assertEq(storedFees, fees24h);
        assertEq(storedApr, apr);
        assertTrue(isActive);
        assertGt(lastUpdated, 0);

        // Check totals
        assertEq(analytics.getTotalPools(), 1);
        assertEq(analytics.getTotalTrackedTokens(), 2);
    }

    function testUpdatePoolDataOnlyAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("Not Authorized");
        analytics.updatePoolData(
            makeAddr("pool"), address(tokenA), address(tokenB), dexRouter, "Test", 1000, 100, 10, 1000
        );
    }

    function testUpdatePoolDataInvalidAddress() public {
        vm.expectRevert("Invalid Pool address");
        analytics.updatePoolData(address(0), address(tokenA), address(tokenB), dexRouter, "Test", 1000, 100, 10, 1000);
    }

    function testUpdateTokenPrice() public {
        uint256 price = 1800 * 10 ** 18; // $1800

        vm.expectEmit(true, false, false, true);
        emit PriceUpdated(address(tokenA), price, block.timestamp);

        analytics.updateTokenPrice(address(tokenA), price);

        // Check token metrics
        (
            address token,
            string memory symbol,
            uint256 storedPrice,
            uint256 totalLiquidity,
            uint256 volume24h,
            uint256 poolCount,
            uint256 lastUpdated
        ) = analytics.tokenMetrics(address(tokenA));

        assertEq(token, address(tokenA));
        assertEq(symbol, "TKNA");
        assertEq(storedPrice, price);
        assertEq(totalLiquidity, 0); // No pools added yet
        assertEq(volume24h, 0);
        assertEq(poolCount, 0);
        assertGt(lastUpdated, 0);
    }

    function testUpdateTokenPriceOnlyAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("Not Authorized");
        analytics.updateTokenPrice(address(tokenA), 1000 * 10 ** 18);
    }

    function testUpdateTokenPriceInvalidAddress() public {
        //Invalid Token Address
        vm.expectRevert("Invalid Token");
        analytics.updateTokenPrice(address(0), 1000 * 10 ** 18);

        //Invalid Price
        vm.expectRevert("Invalid Price");
        analytics.updateTokenPrice(address(tokenA), 0);
    }

    function testgetPoolsForPair() public {
        address pool1 = makeAddr("pool1");
        address pool2 = makeAddr("pool2");
        address pool3 = makeAddr("pool3");

        analytics.updatePoolData(
            pool1,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Uniswap V2",
            1000000 * 10 ** 18,
            50000 * 10 ** 18,
            500 * 10 ** 18,
            1200
        );

        analytics.updatePoolData(
            pool2,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "SushiSwap",
            800000 * 10 ** 18,
            40000 * 10 ** 18,
            400 * 10 ** 18,
            1100
        );

        analytics.updatePoolData(
            pool3,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "PancakeSwap",
            500000 * 10 ** 18,
            25000 * 10 ** 18,
            250 * 10 ** 18,
            1000
        );

        LiquidityAnalytics.PoolInfo[] memory pools = analytics.getPoolsForPair(address(tokenA), address(tokenB));

        assertEq(pools.length, 3);
        assertEq(pools[0].poolAddress, pool1);
        assertEq(pools[1].poolAddress, pool2);

        //Get pools for tokenA/tokenB
        pools = analytics.getPoolsForPair(address(tokenA), address(tokenB));
        assertEq(pools.length, 3);
        assertEq(pools[2].poolAddress, pool3);
    }

    function testGetTopPoolsByLiquidity() public {
        address pool1 = makeAddr("pool1");
        address pool2 = makeAddr("pool2");
        address pool3 = makeAddr("pool3");

        // Add pools with different liquidity amounts
        analytics.updatePoolData(
            pool1,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Pool 1",
            500000 * 10 ** 18, // Lowest liquidity
            25000 * 10 ** 18,
            250 * 10 ** 18,
            1000
        );

        analytics.updatePoolData(
            pool2,
            address(tokenA),
            address(tokenC),
            dexRouter,
            "Pool 2",
            1000000 * 10 ** 18, // Highest liquidity
            50000 * 10 ** 18,
            500 * 10 ** 18,
            1200
        );

        analytics.updatePoolData(
            pool3,
            address(tokenB),
            address(tokenC),
            dexRouter,
            "Pool 3",
            750000 * 10 ** 18, // Middle liquidity
            37500 * 10 ** 18,
            375 * 10 ** 18,
            1100
        );

        LiquidityAnalytics.PoolInfo[] memory topPools = analytics.getTopPoolsByLiquidity(2);

        assertEq(topPools.length, 2);
        assertEq(topPools[0].poolAddress, pool2); // Highest liquidity
        assertEq(topPools[1].poolAddress, pool3); // Middle liquidity
        assertTrue(topPools[0].liquidity >= topPools[1].liquidity);
    }

    function testGetTopPoolsByLiquidityInvalidLimit() public {
        vm.expectRevert("Invalid Limit");
        analytics.getTopPoolsByLiquidity(0);
    }

    function testGetVolumeHistory() public {
        address poolAddress = makeAddr("testPool");

        // Add initial pool
        analytics.updatePoolData(
            poolAddress,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Test Pool",
            1000000 * 10 ** 18,
            50000 * 10 ** 18, // Initial volume
            500 * 10 ** 18,
            1200
        );

        // Update pool multiple times to create history
        for (uint256 i = 1; i <= 5; i++) {
            vm.warp(block.timestamp + 1 hours);
            analytics.updatePoolData(
                poolAddress,
                address(tokenA),
                address(tokenB),
                dexRouter,
                "Test Pool",
                1000000 * 10 ** 18,
                (50000 + i * 1000) * 10 ** 18,
                500 * 10 ** 18,
                1200
            );
        }

        // Get volume history (last 3 snapshots)
        LiquidityAnalytics.VolumeSnapshot[] memory history = analytics.getVolumeHistory(poolAddress, 3);

        assertEq(history.length, 3);
        assertEq(history[0].volume, 53000 * 10 ** 18); // 3rd update (50000 + 3*1000)
        assertEq(history[1].volume, 54000 * 10 ** 18); // 4th update (50000 + 4*1000)
        assertEq(history[2].volume, 55000 * 10 ** 18); // 5th update (50000 + 5*1000)
    }

    function testGetVolumeHistoryInvalidRange() public {
        vm.expectRevert("Invalid time range");
        analytics.getVolumeHistory(makeAddr("pool"), 0);

        vm.expectRevert("Invalid time range");
        analytics.getVolumeHistory(makeAddr("pool"), 169); // > MAX_SNAPSHOTS
    }

    function testCalculateImpermanentLoss() public view {
        uint256 initialPrice0 = 1000 * 10 ** 18; // $1000
        uint256 initialPrice1 = 2000 * 10 ** 18; // $2000
        uint256 currentPrice0 = 1200 * 10 ** 18; // $1200 (+20%)
        uint256 currentPrice1 = 2000 * 10 ** 18; // $2000 (no change)
        uint256 amount0 = 100 * 10 ** 18;
        uint256 amount1 = 50 * 10 ** 18;

        uint256 il = analytics.calculateImpermanentLoss(
            initialPrice0, initialPrice1, currentPrice0, currentPrice1, amount0, amount1
        );

        // Should have some impermanent loss when prices diverge
        assertGt(il, 0);
        assertLt(il, 10000); // Should be less than 100%
    }

    function testCalculateImpermanentLossNoPriceDivergence() public view {
        uint256 price0 = 1000 * 10 ** 18;
        uint256 price1 = 2000 * 10 ** 18;
        uint256 amount0 = 100 * 10 ** 18;
        uint256 amount1 = 50 * 10 ** 18;

        // No price change should result in no impermanent loss
        uint256 il = analytics.calculateImpermanentLoss(price0, price1, price0, price1, amount0, amount1);

        assertEq(il, 0);
    }

    function testGetTokenAnalytics() public {
        address pool1 = makeAddr("pool1");
        address pool2 = makeAddr("pool2");

        // Set token price
        analytics.updateTokenPrice(address(tokenA), 1000 * 10 ** 18);

        // Add pools containing tokenA
        analytics.updatePoolData(
            pool1,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Pool 1",
            1000000 * 10 ** 18,
            50000 * 10 ** 18,
            500 * 10 ** 18,
            1200
        );

        analytics.updatePoolData(
            pool2,
            address(tokenA),
            address(tokenC),
            dexRouter,
            "Pool 2",
            800000 * 10 ** 18,
            40000 * 10 ** 18,
            400 * 10 ** 18,
            1100
        );

        (LiquidityAnalytics.TokenMetrics memory metrics, LiquidityAnalytics.PoolInfo[] memory topPools) =
            analytics.getTokenAnalytics(address(tokenA));

        // Check metrics
        assertEq(metrics.token, address(tokenA));
        assertEq(metrics.symbol, "TKNA");
        assertEq(metrics.price, 1000 * 10 ** 18);
        assertEq(metrics.totalLiquidity, 1800000 * 10 ** 18); // Sum of both pools
        assertEq(metrics.volume24h, 90000 * 10 ** 18); // Sum of both pools
        assertEq(metrics.poolCount, 2);

        // Check top pools
        assertEq(topPools.length, 2);
        assertEq(topPools[0].poolAddress, pool1);
        assertEq(topPools[1].poolAddress, pool2);
    }

    function testDeactivatePool() public {
        address poolAddress = makeAddr("testPool");

        // Add pool
        analytics.updatePoolData(
            poolAddress,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Test Pool",
            1000000 * 10 ** 18,
            50000 * 10 ** 18,
            500 * 10 ** 18,
            1200
        );

        // Check initially active
        (,,,,,,,,,, bool isActive) = analytics.pools(poolAddress);
        assertTrue(isActive);

        // Deactivate pool
        analytics.deactivatePool(poolAddress);

        // Check now inactive
        (,,,,,,,,,, isActive) = analytics.pools(poolAddress);
        assertFalse(isActive);
    }

    function testDeactivatePoolOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        analytics.deactivatePool(makeAddr("pool"));
    }

    function testAuthorizedUpdaterCanUpdate() public {
        vm.prank(authorizedUpdater);
        analytics.updatePoolData(
            makeAddr("pool"), address(tokenA), address(tokenB), dexRouter, "Test", 1000, 100, 10, 1000
        );

        assertEq(analytics.getTotalPools(), 1);
    }

    function testTokenMetricsUpdateOnPoolUpdate() public {
        address poolAddress = makeAddr("testPool");

        // Update pool data
        analytics.updatePoolData(
            poolAddress,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Test Pool",
            1000000 * 10 ** 18,
            50000 * 10 ** 18,
            500 * 10 ** 18,
            1200
        );

        // Check that token metrics were updated
        (,,, uint256 totalLiquidity, uint256 volume24h, uint256 poolCount,) = analytics.tokenMetrics(address(tokenA));

        assertEq(totalLiquidity, 1000000 * 10 ** 18);
        assertEq(volume24h, 50000 * 10 ** 18);
        assertEq(poolCount, 1);
    }

    function testMultiplePoolUpdatesCreateHistory() public {
        address poolAddress = makeAddr("testPool");

        // Add initial pool
        analytics.updatePoolData(
            poolAddress,
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Test Pool",
            1000000 * 10 ** 18,
            50000 * 10 ** 18,
            500 * 10 ** 18,
            1200
        );

        // Update multiple times
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + 1 hours);
            analytics.updatePoolData(
                poolAddress,
                address(tokenA),
                address(tokenB),
                dexRouter,
                "Test Pool",
                1000000 * 10 ** 18,
                (50000 + i * 1000) * 10 ** 18,
                500 * 10 ** 18,
                1200
            );
        }

        LiquidityAnalytics.VolumeSnapshot[] memory fullHistory = analytics.getVolumeHistory(poolAddress, 20);

        assertEq(fullHistory.length, 11);
    }

    // Fuzz Tests
    function testFuzzUpdateTokenPrice(uint256 price) public {
        price = bound(price, 1, type(uint128).max);

        analytics.updateTokenPrice(address(tokenA), price);

        (,, uint256 storedPrice,,,,) = analytics.tokenMetrics(address(tokenA));
        assertEq(storedPrice, price);
    }

    function testFuzzCalculateImpermanentLoss(
        uint256 initialPrice0,
        uint256 initialPrice1,
        uint256 currentPrice0,
        uint256 currentPrice1
    ) public view {
        // Bound prices to reasonable values
        initialPrice0 = bound(initialPrice0, 1e15, 1e25); // $0.001 to $10M
        initialPrice1 = bound(initialPrice1, 1e15, 1e25);
        currentPrice0 = bound(currentPrice0, 1e15, 1e25);
        currentPrice1 = bound(currentPrice1, 1e15, 1e25);

        uint256 amount0 = 100 * 10 ** 18;
        uint256 amount1 = 50 * 10 ** 18;

        uint256 il = analytics.calculateImpermanentLoss(
            initialPrice0, initialPrice1, currentPrice0, currentPrice1, amount0, amount1
        );

        // IL should never exceed 100%
        assertLe(il, 10000);
    }

    receive() external payable {}
}
