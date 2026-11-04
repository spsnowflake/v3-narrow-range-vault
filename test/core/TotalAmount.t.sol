// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SqrtPriceMath} from "uniswap-v3-core/contracts/libraries/SqrtPriceMath.sol";
import {PoolSwapCallback} from "../Abstract/PoolSwapCallback.sol";



contract TotalAmountTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");


    // 测试当价格在中间区间时的总资产。
    function test_totalAmountMiddleRange() public {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, uint256 usdcCount, uint256 wethCount) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertTrue(usdcCount > 0);
        assertTrue(wethCount > 0);
        assertEq(vault.balanceOf(user1), shares);
        vm.stopPrank();

// 在发起swap之前，当前价格下的资产与总资产应该是相等的。
        (uint160 sqrtPriceX96,, , ,,,) = pool.slot0();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(vault.tickLower());
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(vault.tickUpper());
        uint256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, liquidity, false);
        uint256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, liquidity, false);
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        assertEq(totalUsdc, address(usdc) == pool.token0() ? amount0 : amount1);
        assertEq(totalWeth, address(weth) == pool.token1() ? amount1 : amount0);
        assertTrue(totalUsdc > 0 );
        assertTrue(totalWeth > 0 );

        // 要先stop，再发起swap。价格还处于中间，但是跟原本价格不同。此处产生u手续费
        pool.swap(
            address(this),
            false, // false 价格上涨，tick 变大
            1000e18,
            TickMath.getSqrtRatioAtTick(30),
            ""
        );

        // 此处产生weth手续费
        pool.swap(
            address(this),
            true, // true 价格下跌，tick 变小
            1000e18,
            TickMath.getSqrtRatioAtTick(-30),
            ""
        );
        (sqrtPriceX96, , , ,,,) = pool.slot0();
        sqrtLower = TickMath.getSqrtRatioAtTick(vault.tickLower());
        sqrtUpper = TickMath.getSqrtRatioAtTick(vault.tickUpper());
        assertTrue(sqrtPriceX96 > sqrtLower);
        assertTrue(sqrtPriceX96 < sqrtUpper);
        amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, liquidity, false);
        amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, liquidity, false);
// 当前价格下的资产
        uint256 currentUsdc = address(usdc)==pool.token0()? amount0:amount1;
        uint256 currentWeth = address(weth)==pool.token1()? amount1:amount0;

        // 价格在区间中间时，两个资产都有。
        ( totalUsdc,  totalWeth) = vault.totalAmount();
        assertTrue(totalUsdc > 0 );
        assertTrue(totalWeth > 0 );

        // 产生了手续费,所以总资产 - 当下资产,是大于0的.
        assertTrue(totalUsdc - currentUsdc > 0);
        assertTrue(totalWeth - currentWeth > 0);

// 测试计算总资产时，金库的闲置资产会被计算进去。
        (uint256 beforeUsdc, uint256 beforeWeth) = vault.totalAmount();
        usdc.transfer(address(vault), 100e18);
        weth.transfer(address(vault), 100e18);
        (uint256 afterUsdc, uint256 afterWeth) = vault.totalAmount();
        assertEq(afterUsdc - beforeUsdc, 100e18);
        assertEq(afterWeth - beforeWeth, 100e18);
    }



     // 测试当价格在上方区间时的总资产。
     function test_totalAmountAboveRange() public {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, uint256 usdcCount, uint256 wethCount) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertTrue(usdcCount > 0);
        assertTrue(wethCount > 0);
        assertEq(vault.balanceOf(user1), shares);
        vm.stopPrank();

// 要先stop，再发起swap。让价格在上方区间。
        pool.swap(
            address(this),
            false, // false 价格上涨，tick 变大
            10000e18,
            TickMath.getSqrtRatioAtTick(120),
            ""
        );
// 价格在上方区间时，总资产只有token1。
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(vault.tickLower());
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(vault.tickUpper());
        uint256 token1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, false);
        uint256 fee;
        if(address(usdc) == address(pool.token0())){
            assertTrue(totalUsdc==0);
            assertTrue(totalWeth>0);
            fee = totalWeth - token1;
        } else {
            assertTrue(totalUsdc>0);
            assertTrue(totalWeth==0);
            fee = totalUsdc - token1;
        }
        // 手续费大于0，远小于本金
        assertGt(fee, 0);
        assertLt(fee, token1 / 100);
     }


    // 测试当价格在下方区间时的总资产。
    function test_totalAmountBelowRange() public {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, uint256 usdcCount, uint256 wethCount) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertTrue(usdcCount > 0);
        assertTrue(wethCount > 0);
        assertEq(vault.balanceOf(user1), shares);
        vm.stopPrank();

// 要先stop，再发起swap。让价格在下方区间。
        pool.swap(
            address(this),
            true, // true 价格下跌，tick 变小
            10000e18,
            TickMath.getSqrtRatioAtTick(-120),
            ""
        );
// 价格在下方区间时，总资产只有token0。
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
         uint160 sqrtLower = TickMath.getSqrtRatioAtTick(vault.tickLower());
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(vault.tickUpper());
        uint256 token0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, false);
        uint256 fee;
        if(address(usdc) == address(pool.token0())){
            assertTrue(totalUsdc>0);
            assertTrue(totalWeth==0);
            fee = totalUsdc - token0;
        } else {
            assertTrue(totalUsdc==0);
            assertTrue(totalWeth>0);
            fee = totalWeth - token0;
        }
        // 手续费大于0，远小于本金
        assertGt(fee, 0);
        assertLt(fee, token0 / 100);
    }


    
    
    
}