// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PoolSwapCallback} from "../abstract/PoolSwapCallback.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SqrtPriceMath} from "uniswap-v3-core/contracts/libraries/SqrtPriceMath.sol";



contract RedeemFuzzTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");

        // 固定存储一笔，然后以不同份额比例测试赎回数量
    function testFuzz_redeem(uint256 share) public  {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, , , uint256 shares) = vault.deposit(3000e18, 3000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);

        uint256 denominator = vault.totalSupply() + 10**12;

        uint256 sharesBeforeUser1 = vault.balanceOf(user1);

        share = bound(share, 1, vault.balanceOf(user1));
        uint256 usdcBeforeUser1 = usdc.balanceOf(user1);
        uint256 wethBeforeUser1 = weth.balanceOf(user1);
        // user1总资产
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        uint256 calUsdc = Math.mulDiv(totalUsdc, share, denominator);
        uint256 calWeth = Math.mulDiv(totalWeth, share, denominator);
        (uint256 amountUsdc, uint256 amountWeth) = vault.redeem(share);

        uint256 usdcAfterUser1 = usdc.balanceOf(user1);
        uint256 wethAfterUser1 = weth.balanceOf(user1);

        assertEq(amountUsdc, calUsdc);
        assertEq(amountWeth, calWeth);
        assertTrue(amountUsdc < totalUsdc);
        assertTrue(amountWeth < totalWeth);

        assertEq(usdcBeforeUser1 + amountUsdc, usdcAfterUser1);
        assertEq(wethBeforeUser1 + amountWeth, wethAfterUser1);
        assertEq(vault.balanceOf(user1), sharesBeforeUser1 - share);
        
        vm.stopPrank();

    }
}