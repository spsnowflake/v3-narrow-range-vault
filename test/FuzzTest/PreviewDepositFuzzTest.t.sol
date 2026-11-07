// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {PoolSwapCallback} from "../abstract/PoolSwapCallback.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";






contract PreviewDepositFuzzTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");



// 价格在区间内时，流动性由 token0 和 token1 中较小值决定。
    function testFuzz_previewDepositInRangeUsesSmallerAmount( uint256 amount0, uint256 amount1) public  {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        pool.swap(
            address(this),
            false,
            30e18,
            TickMath.getSqrtRatioAtTick(30),
            ""
        );
        amount0 = bound(amount0, 1, 2e24);
        amount1 = bound(amount1, 1, 2e24);
        uint256 usdcCount = address(usdc) == pool.token0() ? amount0 : amount1;
        uint256 wethCount = address(usdc) == pool.token0() ? amount1 : amount0;

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(TICK_UPPER);


        (uint128 liquidity, uint256 amountUsdc,uint256 amountWeth, uint256 shares) = vault.previewDeposit(usdcCount, wethCount);
        uint128 liquidity0 = vault.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, amount0);
        uint128 liquidity1 = vault.getLiquidityForAmount1(sqrtLower, sqrtPriceX96, amount1);
        uint128 liquidityMin = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

        assertEq(liquidity, liquidityMin);
        assertTrue(amountUsdc >0 && amountUsdc <= usdcCount);
        assertTrue(amountWeth >0 && amountWeth <= wethCount);
        assertEq(shares, vault.convertToShares(vault.wethInUsdc(amountWeth) + amountUsdc));
    }


    // 价格在区间上方时，流动性只由 token1 决定。
    function testFuzz_previewDepositAboveRangeUsesAmount1( uint256 amount0, uint256 amount1) public  {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        pool.swap(
            address(this),
            false,
            30e18,
            TickMath.getSqrtRatioAtTick(70),
            ""
        );
        amount0 = bound(amount0, 0, type(uint128).max);
        amount1 = bound(amount1, 1, 2e24);
        uint256 usdcCount = address(usdc) == pool.token0() ? amount0 : amount1;
        uint256 wethCount = address(usdc) == pool.token0() ? amount1 : amount0;

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(TICK_UPPER);


        (uint128 liquidity, uint256 amountUsdc,uint256 amountWeth, uint256 shares) = vault.previewDeposit(usdcCount, wethCount);
        uint128 liquidity2 = vault.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);

        assertEq(liquidity, liquidity2);
        if(address(usdc) == pool.token0()){
            assertTrue(amountWeth >0 && amountWeth <= wethCount);
            assertEq(amountUsdc, 0);

        }else{
            assertTrue(amountUsdc >0 && amountUsdc <= usdcCount);
            assertEq(amountWeth, 0);
        }
        assertEq(shares, vault.convertToShares(vault.wethInUsdc(amountWeth) + amountUsdc));

    }


    // 价格在区间下方时，流动性只由 token0 决定。
    function testFuzz_previewDepositBelowRangeUsesAmount0( uint256 amount0, uint256 amount1) public  {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        pool.swap(
            address(this),
            true,
            30e18,
            TickMath.getSqrtRatioAtTick(-70),
            ""
        );
        amount0 = bound(amount0, 1e12, 1e24);
        amount1 = bound(amount1, 0, type(uint128).max);
        uint256 usdcCount = address(usdc) == pool.token0() ? amount0 : amount1;
        uint256 wethCount = address(usdc) == pool.token0() ? amount1 : amount0;

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(TICK_UPPER);


        (uint128 liquidity, uint256 amountUsdc,uint256 amountWeth, uint256 shares) = vault.previewDeposit(usdcCount, wethCount);
        uint128 liquidity2 = vault.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);

        assertEq(liquidity, liquidity2);
        if(address(usdc) == pool.token0()){
            assertTrue(amountUsdc >0 && amountUsdc <= usdcCount);
            assertEq(amountWeth, 0);
        }else{
            assertTrue(amountWeth >0 && amountWeth <= wethCount);
            assertEq(amountUsdc, 0);
        }
        assertEq(shares, vault.convertToShares(vault.wethInUsdc(amountWeth) + amountUsdc));
    }
}
