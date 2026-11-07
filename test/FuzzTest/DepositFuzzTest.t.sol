// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {PoolSwapCallback} from "../abstract/PoolSwapCallback.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";



contract DepositFuzzTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");


    function testFuzz_deposit(uint256 usdcAmount, uint256 wethAmount) public  {
        usdcAmount = bound(usdcAmount, 1, 1e24);
        wethAmount = bound(wethAmount, 1, 1e24);
        vm.startPrank(user1);
        usdc.mint(user1, usdcAmount);
        weth.mint(user1, wethAmount);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        uint256 sharesBeforeUser1 = vault.balanceOf(user1);
        (uint128 liquidity, uint256 usdcCount,uint256 wethCount, uint256 shares) = vault.deposit(usdcAmount, wethAmount, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertTrue(usdcCount > 0 && usdcCount <= usdcAmount);
        assertTrue(wethCount > 0 && wethCount <= wethAmount);
        uint256 assets = vault.wethInUsdc(wethCount) + usdcCount;
// 份额：assets * (totalSupply() + 10**12) / (totalAssets() + 1)
// 因为前面已经存储了份额,再用上面的公式会错.要复现当时份额,totalSupply为0.
        uint256 shares2 = assets * 10**12 / (vault.totalAssets() + 1);
        uint256 sharesAfterUser1 = vault.balanceOf(user1);
        assertEq(sharesAfterUser1, sharesBeforeUser1 + shares);
        assertEq(shares2, shares);
        assertEq(liquidity , vault.getLiquidity());

    }
}