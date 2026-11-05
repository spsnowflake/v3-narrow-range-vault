// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PoolSwapCallback} from "../Abstract/PoolSwapCallback.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract PreviewRedeemTest is VaultFixture {
    

    address user1 = makeAddr("user1");


    // 测试预估赎回数量
    function test_previewRedeem() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, , ) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        vm.stopPrank();

// 测试份额一半，而不是全部。因为全部份额也就是vault.totalSupply()，shares等于全部份额可能看不出问题。
        uint256 half = shares / 2;
        (uint256 amountUsdc, uint256 amountWeth) = vault.previewRedeem(half, user1);
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        uint256 denominator = vault.totalSupply() + 10 ** 12;
        assertEq(amountUsdc, Math.mulDiv(totalUsdc, half, denominator));
        assertEq(amountWeth, Math.mulDiv(totalWeth, half, denominator));
        assertTrue(amountUsdc > 0);
        assertTrue(amountWeth > 0);

    }



    // 测试赎回份额大于拥有的份额
    function test_redeemMoreThanBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, uint256 usdcCount, uint256 wethCount) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        uint256 redeemAmount = vault.balanceOf(user1) + 1;
        assertTrue(redeemAmount > shares);
        vm.expectRevert("Insufficient balance");
        vault.previewRedeem(redeemAmount, user1);
        vm.stopPrank();

        vault.previewRedeem(shares, user1);

    }
}