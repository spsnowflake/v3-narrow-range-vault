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
import {SqrtPriceMath} from "uniswap-v3-core/contracts/libraries/SqrtPriceMath.sol";



contract RebalanceTest is VaultFixture, PoolSwapCallback {
    address user1 = makeAddr("user1");
    address admin = makeAddr("admin");

    // 只有管理员才能再平衡
    function test_OnlyAdminCanRebalance() public {
        vm.startPrank(user1);
        vm.expectRevert("Only admin can call this function");
        vault.rebalance(0, 60);
        vm.stopPrank();
    }

// 测试再平衡时，新区间铸造失败，币不够。以及流动性为0时，再平衡不会触发burn0的revert。
    function test_RebalanceNotEnoughCoinsAndNotBurn0() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidityUser1, uint256 sharesUser1,,) = vault.deposit(3000e18, 3000e18, 0, user1);
        assertTrue(liquidityUser1 > 0);
        assertTrue(sharesUser1 > 0);
        vm.stopPrank();

        usdc.mint(address(this), 6000e18);
        weth.mint(address(this), 6000e18);
        pool.swap(
            address(this),
            false,
            6000e18,
            TickMath.getSqrtRatioAtTick(80),
            ""
        );
        vm.warp(block.timestamp + 1800);

        (uint256 totalAmountUsdc, uint256 totalAmountWeth) = vault.totalAmount();

// 再平衡失败，新仓没有铸出，代币不够。币留在金库里。
        vm.startPrank(admin);
        (uint128 newLiquidity, uint256 newUsdc, uint256 newWeth) = vault.rebalance(60, 120);
        vm.stopPrank();
        assertTrue(newLiquidity == 0);
        assertTrue(newUsdc == 0);
        assertTrue(newWeth == 0);
        assertEq(usdc.balanceOf(address(vault)), totalAmountUsdc);
        assertEq(weth.balanceOf(address(vault)), totalAmountWeth);

        bytes32 positionKey = keccak256(abi.encodePacked(address(vault), int24(60), int24(120)));
        (uint128 liquidity,,,,) = pool.positions(positionKey);
        assertEq(liquidity, 0);
        assertEq(vault.tickLower(), 60);
        assertEq(vault.tickUpper(), 120);
        
        // 流动性为0时，再平衡不会触发revert，V3池子 burn0会触发revert。
        vm.startPrank(admin);
        (uint128 newLiquidity2, uint256 newUsdc2, uint256 newWeth2) = vault.rebalance(60, 120);
        assertTrue(newLiquidity2 == 0);
        assertTrue(newUsdc2 == 0);
        assertTrue(newWeth2 == 0);
        vm.stopPrank();
    }



// 测试再平衡成功的情况
    function test_RebalanceSuccess() public {

        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidityUser1, uint256 sharesUser1,,) = vault.deposit(3000e18, 3000e18, 0, user1);
        assertTrue(liquidityUser1 > 0);
        assertTrue(sharesUser1 > 0);
        vm.stopPrank();

        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        pool.swap(
            address(this),
            false,
            3000e18,
            TickMath.getSqrtRatioAtTick(40),
            ""
        );
        vm.warp(block.timestamp + 1800);

        (uint256 totalAmountUsdc, uint256 totalAmountWeth) = vault.totalAmount();

        vm.startPrank(admin);
        (uint128 newLiquidity, uint256 newUsdc, uint256 newWeth) = vault.rebalance(0, 60);
        vm.stopPrank();
        
        assertTrue(newLiquidity > 0);
        assertTrue(newUsdc > 0);
        assertTrue(newWeth > 0);
// 金库闲置资产至少有一种大于0
        assertTrue(usdc.balanceOf(address(vault)) > 0 || weth.balanceOf(address(vault)) > 0);
        bytes32 positionKey = keccak256(abi.encodePacked(address(vault), int24(0), int24(60)));
        (uint128 liquidity,,,,) = pool.positions(positionKey);
        assertEq(liquidity, newLiquidity);

        assertEq(totalAmountUsdc,newUsdc+usdc.balanceOf(address(vault)));
        assertEq(totalAmountWeth,newWeth+weth.balanceOf(address(vault)));
    }


    // 测试再平衡时，平均tick不在新区间内的情况
    function test_AverageTickNotInNewRange() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidityUser1, uint256 sharesUser1,,) = vault.deposit(3000e18, 3000e18, 0, user1);
        assertTrue(liquidityUser1 > 0);
        assertTrue(sharesUser1 > 0);
        vm.stopPrank();

// 价格在区间上方，再平衡失败
        usdc.mint(address(this), 300000e18);
        weth.mint(address(this), 300000e18);
        pool.swap(
            address(this),
            true,
            300000e18,
            TickMath.getSqrtRatioAtTick(-12030),
            ""
        );
        vm.warp(block.timestamp + 1800);

        vm.startPrank(admin);
        vm.expectRevert("averageTick must be between newTickLower and newTickUpper");
        vault.rebalance(-240, 240);
        vm.stopPrank();

// 价格在区间下方，再平衡失败
        usdc.mint(address(this), 300000e18);
        weth.mint(address(this), 300000e18);
        pool.swap(
            address(this),
            false,
            300000e18,
            TickMath.getSqrtRatioAtTick(60),
            ""
        );
        vm.warp(block.timestamp + 1800);

        vm.startPrank(admin);
        vm.expectRevert("averageTick must be between newTickLower and newTickUpper");
        vault.rebalance(-120, 0);
        vm.stopPrank();

    }

// 测试再平衡时，下界和上界不能被 tickSpacing 整除的情况
    function test_NotDivisibleByTickSpacing() public {
        vm.startPrank(admin);
        vm.expectRevert("newTickLower and newTickUpper must be divisible by tickSpacing");
        vault.rebalance(60, 61);

        vm.expectRevert("newTickLower and newTickUpper must be divisible by tickSpacing");
        vault.rebalance(51, 60);
        vm.stopPrank();
    }

// 测试再平衡时，下界大于上界的情况
    function test_LowerMoreThanUpper() public {
        vm.startPrank(admin);
        vm.expectRevert("newTickLower must be less than newTickUpper");
        vault.rebalance(60, 0);
        vm.stopPrank();
    }


    
}