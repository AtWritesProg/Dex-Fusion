# DexFusion - Multi-DEX Aggregator

A decentralized exchange aggregator that routes token swaps across multiple DEXs to find the best rates, with built-in liquidity analytics and portfolio tracking capabilities.

## Features

- **Multi-DEX Aggregation**: Automatically finds best swap rates across Uniswap V2/V3, SushiSwap, PancakeSwap
- **Liquidity Analytics**: Real-time pool metrics, volume tracking, and impermanent loss calculations
- **Gas Optimization**: Efficient routing to minimize transaction costs
- **Portfolio Insights**: Track balances, transaction history, and P&L
- **Cross-Chain Ready**: Supports Ethereum, BSC, Polygon (expandable architecture)

## Architecture

### Smart Contracts

- **`DexFusionAggregator.sol`**: Main aggregation logic and swap execution
- **`LiquidityAnalytics.sol`**: Pool analytics and metrics tracking
- **`TestERC20.sol`**: Test tokens for development

### Key Components

- Route optimization across multiple DEXs
- Slippage protection and deadline enforcement
- Platform fee management (0.3% default)
- Real-time price and liquidity data
- Impermanent loss calculations

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolchain
- [Node.js](https://nodejs.org/) - For frontend development
- [Git](https://git-scm.com/) - Version control

Contract Addresses
Sepolia Testnet

DexFusionAggregator: 0x73A61b847b030a2F84cb6DD59c6A6Dc59AdcB6f4

LiquidityAnalytics: 0xFB45bcC417a72ad5c6877C6359869f5c9d21c2dD

Test Tokens (Sepolia)

USDC: 0xa89DD3caD594FAa733B42f9595d8fE39CF1213b7

WETH: 0xFB25e0f3FcC0ED827E1487126bbe159a7cA677a0

DAI: 0x706d4B7e1AD0B4171b261CA8A77EdaE3B9d75763

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/dexfusion
cd dexfusion
