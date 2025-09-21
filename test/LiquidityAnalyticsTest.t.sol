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

    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;

    event PoolDataUpdated(
        address indexed pool,
        address indexed dex,
        uint256 liquidity,
        uint256 volume24h,
        uint256 timestamp
    );

    event PriceUpdated(
        address indexed token,
        uint256 price,
        uint256 timestamp
    );

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
        tokenC = new TestERC20("Token C", "TKNC", 6, INITIAL_BALANCE / 10**12);

        // Set up authorized updater
        analytics.setAuthorizedUpdater(authorizedUpdater, true);
    }

    function testDeployment() public {
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

    // function testUpdatePoolData() public {
    //     address poolAddress = makeAddr("TestPool");
    //     uint256 liquidity = 1000000 * 10**18;
    //     uint256 volume24h = 50000 * 10**18;
    //     uint256 fees24h = 500 * 10**18;
    //     uint256 apr = 1200;

    //     vm.expectEmit(true,true,false,true);
    //     emit PoolDataUpdated(poolAddress, dexRouter, liquidity, volume24h, block.timestamp);

    //     analytics.updatePoolData(
    //         poolAddress,
    //         address(tokenA),
    //         address(tokenB),
    //         dexRouter,
    //         "Uniswap V2",
    //         liquidity,
    //         volume24h,
    //         fees24h,
    //         apr
    //     );

    //     (
    //         address pool,
    //         address token0,
    //         address token1,
    //         address router,
    //         string memory dexName,
    //         uint256 storedLiquidity,
    //         uint256 storedVolume,
    //         uint256 storedFees,
    //         uint256 storedApr,
    //         uint256 lastUpdated,
    //         bool isActive
    //     ) = analytics.pools(poolAddress);

    //     assertEq(pool, poolAddress);
    //     assertEq(token0, address(tokenA));
    //     assertEq(token1, address(tokenB));
    //     assertEq(router, dexRouter);
    //     assertEq(dexName, "Uniswap V2");
    //     assertEq(storedLiquidity, liquidity);
    //     assertEq(storedVolume, volume24h);
    //     assertEq(storedFees, fees24h);
    //     assertEq(storedApr, apr);
    //     assertTrue(isActive);
    //     assertGt(lastUpdated, 0);

    //     // Check totals
    //     assertEq(analytics.getTotalPools(), 1);
    //     assertEq(analytics.getTotalTrackedTokens(), 2);
    // }

    function testUpdatePoolDataOnlyAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("Not Authorized");
        analytics.updatePoolData(
            makeAddr("pool"),
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Test",
            1000,
            100,
            10,
            1000
        );
    }

    function testUpdatePoolDataInvalidAddress() public {
        vm.expectRevert("Invalid Pool address");
        analytics.updatePoolData(
            address(0),
            address(tokenA),
            address(tokenB),
            dexRouter,
            "Test",
            1000,
            100,
            10,
            1000
        );
    }

    function testUpdateTokenPrice() public {
        uint256 price = 1800 * 10**18; // $1800

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


}
