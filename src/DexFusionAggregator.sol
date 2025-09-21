//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DexFusionAggregator
 * @dev Main aggregator contract that routes swaps across multiple DEXs
 * Supports Uniswap V2/V3 SushiSwap, PancakeSwap, and other compatible DEXs
 */

// Move the interface outside the contract
interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLIMITx96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

contract DexFusionAggregator is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Events 
    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address dex,
        uint256 fee
    );

    event DexAdded(address indexed dex, string name, bool isActive);
    event FeeUpdated(uint256 oldFee, uint256 newFee);

    struct DexInfo {
        address router;
        string name;
        bool isActive;
        uint256 fee;
        uint8 dexType;
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        address dexRouter;
        bytes swapData;
        uint256 deadline;
        uint24 poolFee;
    }

    struct RouteQuote {
        address dexRouter;
        uint256 amountOut;
        uint256 gasEstimate;
        uint256 fee;
        string dexName;
    }

    mapping(address => DexInfo) public supportedDexs;
    address[] public dexList;
    uint256 public platformFee = 30;  //0.3% in basis points
    address public feeRecipient;
    uint256 public constant MAX_SLIPPAGE = 5000;  //50% max slippage

    // DEX type constant
    uint8 public constant UNISWAP_V2_TYPE = 0;
    uint8 public constant UNISWAP_V3_TYPE = 1;

    constructor(address _feeRecipient) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient"); // Add this
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Add a new DEX to the aggregator
     */
    function addDex(address _router, string memory _name, uint256 _fee, uint8 _dexType) external onlyOwner {
        require(_router != address(0), "Invalid router address");
        require(_fee <= 1000, "Fee too high");
        require(_dexType <= 1, "Invalid DEX type");

        supportedDexs[_router] = DexInfo({
            router: _router,
            name: _name,
            isActive: true,
            fee: _fee,
            dexType: _dexType
        });

        dexList.push(_router);
        emit DexAdded(_router, _name, true);
    }

    /**
     * @dev Execute a swap through the specified DEX
     */
    function executeSwap(SwapParams memory params) external nonReentrant returns (uint256 amountOut) {
        require(params.deadline >= block.timestamp, "Swap Expired");
        require(supportedDexs[params.dexRouter].isActive, "DEX not supported");
        require(params.amountIn > 0, "Invalid Amount");

        IERC20(params.tokenIn).safeTransferFrom(msg.sender,address(this),params.amountIn);

        uint256 feeAmount = (params.amountIn * platformFee) / 10000;
        uint256 swapAmount = params.amountIn - feeAmount;

        //Transfer Fee to recipient

        if (feeAmount > 0) {
            IERC20(params.tokenIn).safeTransfer(feeRecipient, feeAmount);
        }

        // Approve DEX router
        IERC20(params.tokenIn).safeIncreaseAllowance(params.dexRouter, swapAmount);

        //Execute swap based on DEX type
        amountOut = _executeSwapOnDex(params, swapAmount);

        require(amountOut >= params.amountOutMin, "Insufficient output amount");

        // Transfer output tokens to user
        IERC20(params.tokenOut).safeTransfer(msg.sender, amountOut);

        emit SwapExecuted(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.dexRouter,
            feeAmount
        );
    }

    /**
     * @dev Internal function to execute swap on specific DEX
     */
    function _executeSwapOnDex(
        SwapParams memory params,
        uint256 swapAmount
    ) internal returns (uint256 amountOut) {
        DexInfo memory dexInfo = supportedDexs[params.dexRouter];

        if (dexInfo.dexType == UNISWAP_V2_TYPE) {
            amountOut = _executeUniswapV2Swap(params, swapAmount);
        } else if (dexInfo.dexType ==  UNISWAP_V3_TYPE) {
            amountOut = _executeUniswapV3Swap(params, swapAmount);
        } else {
            revert("Unsupported DEX type");
        }
    }

    /**
     * @dev Execute Uniswap V2 style swap
     */
    function _executeUniswapV2Swap(SwapParams memory params, uint256 swapAmount) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        uint256 balanceBefore = IERC20(params.tokenOut).balanceOf(address(this));

        IUniswapV2Router(params.dexRouter).swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            address(this),
            params.deadline
        );

        uint256 balanceAfter = IERC20(params.tokenOut).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
    }

    function _executeUniswapV3Swap(
        SwapParams memory params,
        uint256 swapAmount
    ) internal returns (uint256 amountOut) {
        IUniswapV3Router.ExactInputSingleParams memory v3Params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.poolFee,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: swapAmount,
            amountOutMinimum: 0,
            sqrtPriceLIMITx96: 0
        });
        amountOut = IUniswapV3Router(params.dexRouter).exactInputSingle(v3Params);
    }

    /**
     * @dev Get quotes from all supported DEXs
     */

    function getAllQuotes(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (RouteQuote[] memory quotes) {
        uint256 activeCount = 0;

        // Count active DEXs
        for (uint256 i = 0; i < dexList.length; i++) {
            if (supportedDexs[dexList[i]].isActive) {
                activeCount++;
            }
        }

        quotes = new RouteQuote[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < dexList.length; i++) {
            address dexRouter = dexList[i];
            if (supportedDexs[dexRouter].isActive) {
                try this.getQuoteFromDex(tokenIn, tokenOut, amountIn, dexRouter)
                returns (uint256 amountOut) {
                    quotes[index] = RouteQuote({
                        dexRouter: dexRouter,
                        amountOut: amountOut,
                        gasEstimate: _estimateGas(dexRouter),
                        fee: supportedDexs[dexRouter].fee,
                        dexName: supportedDexs[dexRouter].name
                    });
                    index++;
                } catch {
                    continue;
                }
            }
        }

        // Resize array to actual count
        assembly {
            mstore(quotes, index)
        }
    }


    function getQuoteFromDex(address tokenIn, address tokenOut, uint256 amountIn, address dexRouter) external view returns (uint256 amountOut) {
        require(supportedDexs[dexRouter].isActive, "Dex not Active");

        // Only support V2 style quotes for now
        if (supportedDexs[dexRouter].dexType == UNISWAP_V2_TYPE) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            try IUniswapV2Router(dexRouter).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
                amountOut = amounts[1];
            } catch {
                amountOut = 0;
            }
        } else {
            amountOut = 0;
        }
    }

    function toggleDexStatus(address dexRouter) external onlyOwner {
       require(supportedDexs[dexRouter].router != address(0), "DEX not found");
       supportedDexs[dexRouter].isActive = !supportedDexs[dexRouter].isActive;
   }

    /**
     * @dev Find the best routes for a swap
     */

    function findBestRoute(address tokenIn, address tokenOut, uint256 amountIn)external view returns (address bestDex, uint256 bestAmountOut){
        RouteQuote[] memory quotes = this.getAllQuotes(tokenIn, tokenOut, amountIn);

        bestAmountOut = 0;
        bestDex = address(0);

        for (uint256 i = 0; i < quotes.length; i++) {
            if (quotes[i].amountOut > bestAmountOut) {
                bestAmountOut = quotes[i].amountOut;
                bestDex = quotes[i].dexRouter;
            }
        }
    }

    /**
     * @dev Estimate gas for DEX swap
     */

    function _estimateGas(address dexRouter) internal view returns (uint256) {
        DexInfo memory dexInfo = supportedDexs[dexRouter];
        if(dexInfo.dexType == UNISWAP_V2_TYPE) {
            return 150000;
        } else if (dexInfo.dexType == UNISWAP_V3_TYPE) {
            return 180000;
        }
        return 0;
    }

    /**
     * @dev Update platform fee 
     */

    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000 , "Fee too high");
        uint256 oldFee = platformFee;
        platformFee = _newFee;
        emit FeeUpdated(oldFee, _newFee);
    }

    /**
     * @dev Update fee recipient
     */
    function updateFeeRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid address");
        feeRecipient = _newRecipient;
    }

    /**
     * @dev Emergency Function to recover stuck tokens
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Get total number of supported DEXs
     */
    function getTotalDexs() external view returns (uint256) {
        return dexList.length;
    }

    /**
     * @dev Get all active DEXs
     */
    function getActiveDexs() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active DEXs
        for (uint256 i = 0; i < dexList.length; i++) {
            if (supportedDexs[dexList[i]].isActive) {
                activeCount++;
            }
        }

        address[] memory activeDexs = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < dexList.length; i++) {
            if (supportedDexs[dexList[i]].isActive) {
                activeDexs[index] = dexList[i];
                index++;
            }
        }
        return activeDexs;
    }

}
