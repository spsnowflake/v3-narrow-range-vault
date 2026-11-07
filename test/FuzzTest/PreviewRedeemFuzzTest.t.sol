// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {PoolSwapCallback} from "../abstract/PoolSwapCallback.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract PreviewRedeemFuzzTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");


    function testFuzz_previewRedeem(uint256 share) public  {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, , ) = vault.deposit(3000e18, 3000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        vm.stopPrank();

// 固定存储一笔，然后以不同份额比例测试预估赎回数量
        share = bound(share, 1, vault.balanceOf(user1));
        (uint256 amountUsdc, uint256 amountWeth) = vault.previewRedeem(share, user1);
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        uint256 denominator = vault.totalSupply() + 10**12;
        assertEq(amountUsdc, Math.mulDiv(totalUsdc, share, denominator));
        assertEq(amountWeth, Math.mulDiv(totalWeth, share, denominator));
        assertLe(amountUsdc, totalUsdc);
        assertLe(amountWeth, totalWeth);
    }
}