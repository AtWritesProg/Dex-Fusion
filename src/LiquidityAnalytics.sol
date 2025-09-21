// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Liquidity Analytics
 * @dev A contract to track and analyze liquidity provision and removal events.
 * Provides real-time data on pools, volumes and liquidity metrics.
 */

contract LiquidityAnalytics is Ownable {
    
    // Events
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

    // Structs

    struct PoolInfo {
        address poolAddress;
        address token0;
        address token1;
        address dexRouter;
        string dexName;
        uint256 liquidity; //Total Liquidity in USD
        uint256 volume24h; //24h volume in USD
        uint256 fees24h;
        uint256 apr;    // Annual Percentage rate
        uint256 lastUpdated;
        bool isActive;
    }

    struct TokenMetrics {
        address token;
        string symbol;
        uint256 price;
        uint256 totalLiquidity; // Total liquidity across all pools
        uint256 volume24h; // Total 24h volume
        uint256 poolCount; // Number of pools containing this token
        uint256 lastUpdated;
    }

    struct VolumeSnapshot {
        uint256 timestamp;
        uint256 volume;
        uint256 liquidity;
        uint256 price;
    }

    //State Variable
    mapping(address => PoolInfo) public pools;
    mapping(address => TokenMetrics) public tokenMetrics;
    mapping(address => VolumeSnapshot[]) public volumeHistory;
    mapping(address => bool) public authorizedUpdaters;

    address[] public allPools;
    address[] public trackedTokens;

    uint256 public constant SNAPSHOT_INTERVAL = 1 hours;
    uint256 public constant MAX_SNAPSHOTS = 168; // 1 week of hourly data

    
    //Modifier
    modifier onlyAuthorized() {
        require(
            authorizedUpdaters[msg.sender] || msg.sender == owner(),
            "Not Authorized"
        );
        _;
    }

    constructor() Ownable(msg.sender) {
        authorizedUpdaters[msg.sender] = true;
    }

    function updatePoolData(
        address poolAddress,
        address token0,
        address token1,
        address dexRouter,
        string memory dexName,
        uint256 liquidity,
        uint256 volume24h,
        uint256 fees24h,
        uint256 apr
        ) external onlyAuthorized{
            require(poolAddress != address(0), "Invalid Pool address");

            bool isNewPool = pools[poolAddress].poolAddress == address(0);

            pools[poolAddress] = PoolInfo({
                poolAddress: poolAddress,
                token0: token0,
                token1: token1,
                dexRouter: dexRouter,
                dexName: dexName,
                liquidity: liquidity,
                volume24h: volume24h,
                fees24h: fees24h,
                apr: apr,
                lastUpdated: block.timestamp,
                isActive: true
            });

            if (isNewPool) {
                allPools.push(poolAddress);
            }

            _updateTokenMetrics(token0);
            _updateTokenMetrics(token1);

            
            _addVolumeSnapshot(poolAddress, volume24h, liquidity, 0);

            emit PoolDataUpdated(poolAddress, dexRouter, liquidity, volume24h, block.timestamp);
        }

        /**
         * @dev Update token price
         */

        function updateTokenPrice(address token, uint256 price) external onlyAuthorized {
            require(token != address(0), "Invalid Token");
            require(price > 0, "Invalid Price");

            if (tokenMetrics[token].token == address(0)) {
                _initializeTokenMetrics(token);
            }

            tokenMetrics[token].price = price;
            tokenMetrics[token].lastUpdated = block.timestamp;

            emit PriceUpdated(token, price, block.timestamp);
        }

        /**
         * @dev
         */
        function getPoolsForPair(address token0, address token1) external view returns (PoolInfo[] memory) {
            uint256 count = 0;
            
            // Count Matching Pool
            for (uint256 i = 0; i < allPools.length; i++) {
                PoolInfo memory pool = pools[allPools[i]];
                if(pool.isActive &&
                ((pool.token0 == token0 && pool.token1 == token1) ||
                (pool.token0 == token1 && pool.token1 == token0))) {
                    count++;
                }
            }

            PoolInfo[] memory result = new PoolInfo[](count);
            uint256 index = 0;

            for (uint256 i = 0; i < allPools.length; i++) {
                PoolInfo memory pool = pools[allPools[i]];
                if (pool.isActive && 
                ((pool.token0 == token0 && pool.token1 == token1) ||
                 (pool.token0 == token1 && pool.token1 == token0))) {
                    result[index] = pool;
                    index++;
                }
            }

            return result;
        }

        /**
         * @dev Get top pools by liquidity
         */
        function getTopPoolsByLiquidity(uint256 limit) external view returns (PoolInfo[] memory) {
            require(limit > 0 && limit < allPools.length, "Invalid Limit");

            PoolInfo[] memory allActivePools = new PoolInfo[](allPools.length);
            uint256 activeCount = 0;

            // Get all active Pool
            for (uint256 i = 0; i < allPools.length; i++) {
                if (pools[allPools[i]].isActive) {
                    allActivePools[activeCount] = pools[allPools[i]];
                    activeCount++;
                }
            }

            // Sort by liquidity
            for (uint256 i =0; i < activeCount-1; i++) {
                for (uint256 j = 0; j < activeCount - i - 1; j++) {
                    if (allActivePools[j].liquidity < allActivePools[j + 1].liquidity) {
                        PoolInfo memory temp = allActivePools[j];
                        allActivePools[j] = allActivePools[j + 1];
                        allActivePools[j + 1] = temp;
                    }
                }
            }

            // Return top N pools
            uint256 returnCount = limit < activeCount ? limit : activeCount;
            PoolInfo[] memory result = new PoolInfo[](returnCount);
            
            for (uint256 i = 0; i < returnCount; i++) {
                result[i] = allActivePools[i];
            }

            return result;
        }

        /**
         * @dev Get Volume history for a pool
         */
        function getVolumeHistory(address poolAddress, uint256 numhours) external view returns (VolumeSnapshot[] memory) {
            require(numhours > 0 && numhours <= MAX_SNAPSHOTS, "Invalid time range");

            VolumeSnapshot[] storage history = volumeHistory[poolAddress];
            uint256 startIndex = history.length > numhours ? history.length - numhours : 0;
            uint256 resultLength = history.length - startIndex;

            VolumeSnapshot[] memory result = new VolumeSnapshot[](resultLength);
        
            for (uint256 i = 0; i < resultLength; i++) {
                result[i] = history[startIndex + i];
            }
            
            return result;
        }

        /**
         * @dev  Calculate Impermanent Loss for a position
         */
        function calculateImpermanentLoss(
            uint256 initialPrice0,
            uint256 initialPrice1,
            uint256 currentPrice0,
            uint256 currentPrice1,
            uint256 amount0,
            uint256 amount1
        ) external pure returns (uint256 impermanentLoss) {
            //Calculate price ratios
            uint256 initialRatio = (initialPrice0 * 1e18) / initialPrice1;
            uint256 currentRatio = (currentPrice0 * 1e18) / currentPrice1;

            // Hodl Value
            uint256 hodlValue = ((amount0 * currentPrice0) +(amount1 * currentPrice1)) / 1e18;

            // Calculate LP value
            uint256 sqrtRatio = sqrt((currentRatio * 1e18) / initialRatio);
            uint256 lpValue = (2* sqrt(amount0 * amount1 * currentPrice0 * currentPrice1)) / 1e18;
            lpValue = (lpValue * sqrtRatio) / 1e9;

            if (hodlValue > lpValue) {
                impermanentLoss = ((hodlValue - lpValue) * 10000) / hodlValue; // In basis points
            } else {
                impermanentLoss = 0;
            }
        }

        /**
         * @dev Get token analytics 
         */
        function getTokenAnalytics(address token) external view returns (
            TokenMetrics memory metrics,
            PoolInfo[] memory topPools
        ) {
            metrics = tokenMetrics[token];

            // Get top 5 pools for this token
            uint256 count = 0;
            for (uint256 i = 0; i < allPools.length; i++) {
                PoolInfo memory pool = pools[allPools[i]];
                if (pool.isActive && (pool.token0 == token || pool.token1 == token)) {
                    count++;
                }
            }

            topPools = new PoolInfo[](count > 5 ? 5 : count);
            uint256 index = 0;

            for (uint256 i = 0; i < allPools.length && index < topPools.length; i++) {
                PoolInfo memory pool = pools[allPools[i]];
                if (pool.isActive && (pool.token0 == token || pool.token1 == token)) {
                    topPools[index] = pool;
                    index++;
                }
            }            
        }

        /**
         * @dev Internal function to update token metrics based on current pool data.
         */

        function _updateTokenMetrics(address token) internal {
            if(tokenMetrics[token].token == address(0)) {
                _initializeTokenMetrics(token);
            }

            uint256 totalLiquidity = 0;
            uint256 totalVolume = 0;
            uint256 poolCount = 0;

            for (uint256 i = 0; i < allPools.length; i++) {
                PoolInfo memory pool = pools[allPools[i]];
                if (pool.isActive && (pool.token0 == token || pool.token1 == token)) {
                totalLiquidity += pool.liquidity;
                totalVolume += pool.volume24h;
                poolCount++;
                }
            }

            tokenMetrics[token].totalLiquidity = totalLiquidity;
            tokenMetrics[token].volume24h = totalVolume;
            tokenMetrics[token].poolCount = poolCount;
            tokenMetrics[token].lastUpdated = block.timestamp;

        }

        function _initializeTokenMetrics(address token) internal {
            // Get token symbol
            string memory symbol = "UNKNOWN";
            try IERC20Metadata(token).symbol() returns (string memory _symbol) {
                symbol = _symbol;
            } catch {}

            tokenMetrics[token] = TokenMetrics({
                token: token,
                symbol: symbol,
                price: 0,
                totalLiquidity: 0,
                volume24h: 0,
                poolCount: 0,
                lastUpdated: block.timestamp
            });

            trackedTokens.push(token);
        }

        function _addVolumeSnapshot(
            address poolAddress,
            uint256 volume,
            uint256 liquidity,
            uint256 price
        ) internal {
            VolumeSnapshot[] storage history = volumeHistory[poolAddress];
    
            //Add new snapshots
            history.push(VolumeSnapshot({
                timestamp: block.timestamp,
                volume: volume,
                liquidity: liquidity,
                price: price
            }));

            // Keep only recent snapshots
            if (history.length > MAX_SNAPSHOTS) {
                for (uint256 i = 0; i < history.length - 1; i++) {
                    history[i] = history[i + 1];
                }

                history.pop();
            }
        }

        function sqrt(uint256 x) internal pure returns (uint256) {
            if (x == 0) return 0;
            uint256 z = (x + 1) / 2;
            uint256 y = x;
            while (z < y) {
                y = z;
                z = (x / z + z ) / 2;
            }
            return y;
        }

        /**
         * @dev Authorize address to update data 
         */
        function setAuthorizedUpdater(address updater, bool authorized) external onlyOwner {
            authorizedUpdaters[updater] = authorized;
        }

        /**
         * @dev Deactivate Pool
         */
        function deactivatePool(address poolAddress) external onlyOwner {
            pools[poolAddress].isActive = false;
        }

        /**
         * @dev Get total number of pools
         */
        function getTotalPools() external view returns (uint256) {
            return allPools.length;
        }

        /**
         * @dev Get total number of tracked tokens 
         */
        function getTotalTrackedTokens() external view returns (uint256) {
            return trackedTokens.length;
        }

}