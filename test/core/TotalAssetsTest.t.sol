// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SqrtPriceMath} from "uniswap-v3-core/contracts/libraries/SqrtPriceMath.sol";
import {PoolSwapCallback} from "../abstract/PoolSwapCallback.sol";




contract TotalAssetsTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");

    // 测试当价格在中间区间时的总资产（折算为u）。
    function test_totalAssetsMiddleRange() public {
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        (uint128 liquidity, uint256 usdcCount, uint256 wethCount, uint256 shares) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(usdcCount > 0);
        assertTrue(wethCount > 0);
        vm.stopPrank();

        pool.swap(
            address(this),
            false, // false 价格上涨，tick 变大
            1000e18,
            TickMath.getSqrtRatioAtTick(30),
            ""
        );

        vm.warp(block.timestamp + 1800);

// 现价跟均价区分开
        pool.swap(
            address(this),
            true, // true 价格下跌，tick 变小
            1000e18,
            TickMath.getSqrtRatioAtTick(-40),
            ""
        );

        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        assertTrue(totalUsdc > 0);
        assertTrue(totalWeth > 0);
        assertEq(vault.totalAssets(), vault.wethInUsdc(totalWeth) + totalUsdc);
    }


}