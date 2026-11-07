// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";




contract ShareInflationTest is VaultFixture {
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    
// 测试ERC4626 份额通胀
    function test_shareInflation() public {
        usdc.mint(user2, 3000e18);
        weth.mint(user2, 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        (uint128 liquidityUser1, uint256 usdcUser1, uint256 wethUser1, uint256 sharesUser1) = vault.deposit(1000, 1000, 0, user1);
        assertTrue(sharesUser1 > 0);
        assertTrue(liquidityUser1 > 0);

        // 直接转账，不经过deposit方法。
        usdc.transfer(address(vault), 10e18);
        vm.stopPrank();

        // 第二个人来存款
        vm.startPrank(user2);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        (uint128 liquidityUser2, uint256 usdcUser2, uint256 wethUser2, uint256 sharesUser2) = vault.deposit(1e18, 1e18, 0, user2);
        // 份额不会被攻击成0
        assertTrue(sharesUser2 > 0);
        assertTrue(liquidityUser2 > 0);
        vm.stopPrank();

        vm.startPrank(user1);
        (uint256 redeemUsdcUser1, uint256 redeemWethUser1) = vault.redeem(sharesUser1);
        vm.stopPrank();

        vm.startPrank(user2);
        (uint256 redeemUsdcUser2, uint256 redeemWethUser2) = vault.redeem(sharesUser2);
        vm.stopPrank();

        // 折价user1前后资产，然后比较
        // 存款所消耗的weth数量，折算成usdc数量
        uint256 depositUsdcUser1WethToUsdc = vault.wethInUsdc(wethUser1);
        // 赎回所得到的weth数量，折算成usdc数量
        uint256 redeemUsdcUser1WethToUsdc = vault.wethInUsdc(redeemWethUser1);
// 统一折算后，再比较，攻击者user1亏了
        assertTrue(redeemUsdcUser1 + redeemUsdcUser1WethToUsdc < usdcUser1 + 10e18 + depositUsdcUser1WethToUsdc);

        

    }
}