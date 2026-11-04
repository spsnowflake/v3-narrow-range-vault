// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";



contract DepositTest is VaultFixture {

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    

// 测试最小份额不满足
    function test_notEnoughShares() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        uint minshares = 1e18;

        uint256 usdcCount = 1000e18;
        uint256 wethCount = 10e18;

        (, uint256 amountUsdc, uint256 amountWeth,) = vault.previewDeposit(usdcCount, wethCount);
        uint256 assets = vault.wethInUsdc(amountWeth) + amountUsdc;
        uint256 shares = assets * 10**12 / (assets + 1);
        assertTrue(shares < minshares);

        vm.expectRevert('Minimum shares not met');
        vault.deposit(usdcCount, wethCount, minshares, user1);
    }

// 测试份额正确
    function test_sharesTrue() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, uint256 usdcCount, uint256 wethCount) = vault.deposit(1000e18, 10e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertTrue(usdcCount > 0);
        assertTrue(wethCount > 0);

        uint256 assets = vault.wethInUsdc(wethCount) + usdcCount;
// 份额：assets * (totalSupply() + 10**12) / (totalAssets() + 1)
// 因为前面已经存储了份额,再用上面的公式会错.要复现当时份额,totalSupply为0.
        uint256 shares2 = assets * 10**12 / (vault.totalAssets() + 1);
        assertEq(shares2, shares);
        
    }

    // 测试deposit 方法成功后，份额发给receiver
    function test_depositToReceiver() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, uint256 shares, uint256 usdc, uint256 weth) = vault.deposit(1000e18, 1000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertTrue(usdc > 0);
        assertTrue(weth > 0);
        assertEq(vault.balanceOf(user1), shares);


        (uint128 liquidity2, uint256 shares2, uint256 usdc2, uint256 weth2) = vault.deposit(2000e18, 2000e18, 0, user2);
        assertTrue(liquidity2 > 0);
        assertTrue(shares2 > 0);
        assertTrue(usdc2 > 0);
        assertTrue(weth2 > 0);
        assertEq(vault.balanceOf(user2), shares2);

        vm.stopPrank();
    }
}