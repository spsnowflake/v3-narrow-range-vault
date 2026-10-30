// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

// 测试 getLiquidityForAmounts 方法
contract GetLiquidityForAmountsTest is VaultFixture {


// 测试处于区间内部时，流动性增加取小的那个。
    function test_insideRangeTakesSmaller() public {
        uint128 liquidityMin;
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(0);
        uint128 liquidity0 = vault.getLiquidityForAmount0(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18);
        uint128 liquidity1 = vault.getLiquidityForAmount1(TickMath.getSqrtRatioAtTick(TICK_LOWER), sqrtRatioX96,3000e18);
        assertTrue(liquidity0 != liquidity1);
        uint128 liquidity = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18,3000e18);
        (liquidityMin, )=(liquidity0 < liquidity1)?  (liquidity0, liquidity1):(liquidity1, liquidity0);
        assertEq(liquidity,liquidityMin);
    }


// 测试高于区间上沿时，token0再多，token1为0时，不增加流动性
    function test_aboveRangeUsesAmount1() public {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(120);
        uint128 liquidity = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18,0);
        assertEq(liquidity, 0);

        // token1 不为0时，流动性增加。
        uint128 liquidityOnlyAmount1 = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),0,3000e18);
        assertTrue(liquidityOnlyAmount1 > 0);
// 高于区间上沿，即便有token0，依然是取token1流动性。
// 数量为正时，结果等于getLiquidityForAmount1
        liquidity = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18,3000e18);
        assertEq(liquidity,vault.getLiquidityForAmount1(TickMath.getSqrtRatioAtTick(TICK_LOWER),TickMath.getSqrtRatioAtTick(TICK_UPPER),3000e18));
    }


// 测试低于区间下沿时，token1再多，token0为0时，不增加流动性。
    function test_belowRangeUsesAmount0() public {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(-120);
        uint128 liquidity = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),0,3000e18);
        assertEq(liquidity, 0);
        // token0 不为0时，流动性增加。
        uint128 liquidityOnlyAmount0 = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18,0);
        assertTrue(liquidityOnlyAmount0 > 0);
// 低于区间下沿，即便有token1，依然是取token0流动性。
// 数量为正时，结果等于getLiquidityForAmount0
        liquidity = vault.getLiquidityForAmounts(sqrtRatioX96, TickMath.getSqrtRatioAtTick(TICK_LOWER), TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18,3000e18);
        assertEq(liquidity,vault.getLiquidityForAmount0(TickMath.getSqrtRatioAtTick(TICK_LOWER),TickMath.getSqrtRatioAtTick(TICK_UPPER),5e18));


    }


}
