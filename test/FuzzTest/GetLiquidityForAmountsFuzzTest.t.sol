// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

contract GetLiquidityForAmountsFuzzTest is VaultFixture {


// 价格在区间内时，流动性由 token0 和 token1 决定。且流动性去较小的那个
    function testFuzz_withinRangeUsesBoth(int24 tick, uint256 amount0, uint256 amount1) public view {
        tick = int24(bound(tick, TICK_LOWER+1, TICK_UPPER-1));
        amount0 = bound(amount0, 1e12, 1e24);
        amount1 = bound(amount1, 1e12, 1e24);
        
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(TICK_UPPER);


        uint128 liquidity = vault.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
        uint128 liquidity0 = vault.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, amount0);
        uint128 liquidity1 = vault.getLiquidityForAmount1(sqrtLower, sqrtPriceX96, amount1);
        if (liquidity0 < liquidity1) {
            assertEq(liquidity, liquidity0);
            assertEq(liquidity, vault.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, amount0));
        } else {
            assertEq(liquidity, liquidity1);
            assertEq(liquidity, vault.getLiquidityForAmount1(sqrtLower, sqrtPriceX96, amount1));
        }
        assertTrue(liquidity>0);
    }





// 价格在区间上沿或更高时，流动性只由 token1 决定。`
    function testFuzz_aboveRangeUsesAmount1(int24 tick, uint256 amount0, uint256 amount1) public view {
        tick = int24(bound(tick, TICK_UPPER, TickMath.MAX_TICK));
        amount0 = bound(amount0, 0, type(uint128).max);
        amount1 = bound(amount1, 1e12, 1e24);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(TICK_UPPER);

        uint128 liquidity = vault.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
        assertEq(liquidity, vault.getLiquidityForAmount1(sqrtLower, sqrtUpper, amount1));
        assertTrue(liquidity>0);
    }


    
    // 价格在区间下沿或更低时，流动性只由 token0 决定。
    function testFuzz_belowRangeUsesAmount0(int24 tick, uint256 amount0, uint256 amount1) public view {
        tick = int24(bound(tick, TickMath.MIN_TICK, TICK_LOWER));
        amount0 = bound(amount0, 1e12, 1e24);
        amount1 = bound(amount1, 0, type(uint128).max);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(TICK_UPPER);

        uint128 liquidity = vault.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1);
        assertEq(liquidity, vault.getLiquidityForAmount0(sqrtLower, sqrtUpper, amount0));
        assertTrue(liquidity>0);
    }
}
