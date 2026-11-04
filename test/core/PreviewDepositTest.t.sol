// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


contract PreviewDepositTest is VaultFixture {

    // 当usdc是token0且价格处于区间中间时,消耗两种token
    function test_TwoTokensAreDepositedWhenPriceIsInRangeAndUsdcIsToken0() public {
        V3NarrowRangeVault vault;
        TestERC20 usdcToken;
        TestERC20 wethToken;
        {
            // 这里通过 create2 让测试里 token0是usdc
            bytes memory usdcInit = abi.encodePacked(type(TestERC20).creationCode, abi.encode("USD Coin", "USDC", uint8(6)));
            bytes memory wethInit = abi.encodePacked(type(TestERC20).creationCode, abi.encode("Wrapped Ether", "WETH", uint8(18)));
            for (uint256 salt = 0; salt < 1000; salt++) {
                address usdcAddr = vm.computeCreate2Address(bytes32(salt), keccak256(usdcInit), address(this));
                address wethAddr = vm.computeCreate2Address(bytes32(salt + 1000), keccak256(wethInit), address(this));
                if (usdcAddr < wethAddr) {
                    usdcToken = new TestERC20{salt: bytes32(salt)}("USD Coin", "USDC", 6);
                    wethToken = new TestERC20{salt: bytes32(salt + 1000)}("Wrapped Ether", "WETH", 18);
                    // 用这两个地址 createPool、initialize，再把 usdcToken 传进构造函数
                    break;
                }
            }
            pool = IUniswapV3Pool(factory.createPool(address(usdcToken), address(wethToken), POOL_FEE));
            pool.initialize(INIT_SQRT_PRICE_X96);
            vault = new V3NarrowRangeVault(pool, IERC20(pool.token0()), TICK_LOWER, TICK_UPPER);

            // 初始化写下的观察点，要至少早于调用 1800 秒，getPrice 和 rebalance 里的 observe 才能用。
            vm.warp(block.timestamp + 1800);
            // 增加观察点，否则 getPrice 和 rebalance 里的 observe 会失败。
            pool.increaseObservationCardinalityNext(2); 
        }
        // 先让价格处于区间中间（-60到60之间）
        pool.swap(address(this), true,1000, TickMath.getSqrtRatioAtTick(-50), "");
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        assertEq(sqrtPriceX96, TickMath.getSqrtRatioAtTick(-50));
        
        uint256 usdcAmount = address(usdcToken) == address(pool.token0()) ? 10000e6 : 10e18;
        uint256 wethAmount = address(usdcToken) == address(pool.token0()) ? 10e18 : 10000e6;
        (uint128 liquidity, uint256 amountUsdc, uint256 amountWeth, uint256 shares) = vault.previewDeposit(usdcAmount, wethAmount);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(TICK_UPPER);
        // USDC 是 token0 时，amount0 必须是 usdcAmount。
        assertEq(
            liquidity,vault.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, usdcAmount, wethAmount));
        assertTrue(
            liquidity != vault.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, wethAmount, usdcAmount));
    }

    // 价格处于区间中间时,消耗两种token
    function test_TwoTokensAreDepositedWhenPriceIsInRange() public {
        // 先让价格处于区间中间（-60到60之间）
        pool.swap(address(this), false,1000, TickMath.getSqrtRatioAtTick(30), "");
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        assertEq(sqrtPriceX96, TickMath.getSqrtRatioAtTick(30));
        
        uint256 usdcAmount = address(usdc) == address(pool.token0()) ? 10e18 : 10000e6;
        uint256 wethAmount = address(usdc) == address(pool.token0()) ? 10000e6 : 10e18;

        (uint128 liquidity, uint256 amountUsdc, uint256 amountWeth, uint256 shares) = vault.previewDeposit(usdcAmount, wethAmount);
        // 返回的用量不超过传入值
        assertTrue(usdcAmount >= amountUsdc);
        assertTrue(wethAmount >= amountWeth);
        // 多出来的那种代币不会被用完。
        if(usdcAmount != amountUsdc) {
            assertTrue(usdcAmount-amountUsdc>0);
        } else {
            assertTrue(wethAmount-amountWeth>0);
        }
        assertTrue(liquidity > 0);
        assertTrue(amountUsdc > 0);
        assertTrue(amountWeth > 0);
        assertTrue(shares > 0);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(TICK_UPPER);

// 入参中，先传入 token0，测试池子的 token0 是 weth
        uint128 liquidity2 = vault.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, wethAmount, usdcAmount);
        assertEq(liquidity, liquidity2);

        assertEq(shares,(vault.wethInUsdc(amountWeth) + amountUsdc) * 10**12);

// 流动性取的是较小的那个
        uint128 liquidity3 = vault.getLiquidityForAmount0(sqrtPriceX96, sqrtRatioBX96, wethAmount);
        uint128 liquidity4 = vault.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, usdcAmount);
        if (liquidity3 < liquidity4) {
            assertEq(liquidity, liquidity3);
        } else {
            assertEq(liquidity, liquidity4);
        }


    }

// 价格处于区间上方时,只消耗token1
    function test_OnlyOneTokenIsDepositedWhenPriceIsAboveRange() public {
        // 先让价格处于区间上方
        pool.swap(address(this), false, 1, TickMath.getSqrtRatioAtTick(120), "");
        (uint128 liquidity, uint256 amountUsdc, uint256 amountWeth, uint256 shares) = vault.previewDeposit(10e18, 10000e6);
        assertTrue(liquidity > 0);
        assertTrue(amountUsdc > 0);
        assertEq(amountWeth, 0);
        assertTrue(shares > 0);
    }
    
    // 价格处于区间下方时,只消耗token0
    function test_OnlyOneTokenIsDepositedWhenPriceIsBelowRange() public {
        // 先让价格处于区间下方
        pool.swap(address(this), true, 1, TickMath.getSqrtRatioAtTick(-120), "");
        (uint128 liquidity, uint256 amountUsdc, uint256 amountWeth, uint256 shares) = vault.previewDeposit(10e18, 10000e6);
        assertTrue(liquidity > 0);
        assertTrue(amountWeth > 0);
        assertEq(amountUsdc, 0);
        assertTrue(shares > 0);
    }

        // 空回调，swap需要。
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external {}


}