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


contract RedeemTest is VaultFixture, PoolSwapCallback {
    

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address admin = makeAddr("admin");

    function test_redeemAll() public {
        usdc.mint(user2, 3000e18);
        weth.mint(user2, 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidityUser1, uint256 sharesUser1,,) = vault.deposit(50e18, 50e18, 0, user1);
        assertTrue(liquidityUser1 > 0);
        assertTrue(sharesUser1 > 0);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        (uint128 liquidityUser2, uint256 sharesUser2,,) = vault.deposit(100e18, 100e18, 0, user2);
        assertTrue(liquidityUser2 > 0);
        assertTrue(sharesUser2 > 0);
        vm.stopPrank();

        sharesUser2 = vault.balanceOf(user2);

// 产生点手续费
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        pool.swap(
            address(this),
            true,
            30e18,
            TickMath.getSqrtRatioAtTick(-50),
            ""
        );

        pool.swap(
            address(this),
            false,
            30e18,
            TickMath.getSqrtRatioAtTick(50),
            ""
        );

        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());
        uint256 user2Token0Before = token0.balanceOf(user2);
        uint256 user2Token1Before = token1.balanceOf(user2);

        uint256 user2AllShares = vault.balanceOf(user2);
        assertTrue(user2AllShares > 0);

        token0.transfer(address(vault), 100e18);
        token1.transfer(address(vault), 100e18);

        (uint256 expectedUsdc, uint256 expectedWeth) = _expectedRedeem(user2AllShares);
        vm.startPrank(user2);
        (uint256 amountUsdc, uint256 amountWeth) = vault.redeem(user2AllShares);
        vm.stopPrank();

        uint256 user2Token0After = token0.balanceOf(user2);
        uint256 user2Token1After = token1.balanceOf(user2);

        assertEq(amountUsdc, expectedUsdc);
        assertEq(amountWeth, expectedWeth);

        // 个人全部赎回后，份额为0
        assertEq(vault.balanceOf(user2), 0);
// 确认用户账户资产增加
        assertEq(user2Token0After, user2Token0Before + (address(token0) == address(weth) ? amountWeth : amountUsdc));
        assertEq(user2Token1After, user2Token1Before + (address(token1) == address(weth) ? amountWeth : amountUsdc));
    }


    function test_partOfRedeem() public {
        usdc.mint(user2, 3000e18);
        weth.mint(user2, 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidityUser1, uint256 sharesUser1,,) = vault.deposit(50e18, 50e18, 0, user1);
        assertTrue(liquidityUser1 > 0);
        assertTrue(sharesUser1 > 0);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        (uint128 liquidityUser2, uint256 sharesUser2,,) = vault.deposit(100e18, 100e18, 0, user2);
        assertTrue(liquidityUser2 > 0);
        assertTrue(sharesUser2 > 0);
        vm.stopPrank();

        sharesUser2 = vault.balanceOf(user2);

// 产生点手续费
        usdc.mint(address(this), 3000e18);
        weth.mint(address(this), 3000e18);
        pool.swap(
            address(this),
            true,
            30e18,
            TickMath.getSqrtRatioAtTick(-50),
            ""
        );

        pool.swap(
            address(this),
            false,
            30e18,
            TickMath.getSqrtRatioAtTick(50),
            ""
        );
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());
        uint256 user2Token0Before = token0.balanceOf(user2);
        uint256 user2Token1Before = token1.balanceOf(user2);

        uint256 half = sharesUser2 / 2;
        token0.transfer(address(vault), 100e18);
        token1.transfer(address(vault), 100e18);
        (uint256 expectedUsdc, uint256 expectedWeth) = _expectedRedeem(half);
        vm.startPrank(user2);
        (uint256 amountUsdc, uint256 amountWeth) = vault.redeem(half);
        vm.stopPrank();
        uint256 user2Token0After = token0.balanceOf(user2);
        uint256 user2Token1After = token1.balanceOf(user2);

        assertEq(amountUsdc, expectedUsdc);
        assertEq(amountWeth, expectedWeth);
// 个人赎回后，份额减少
        assertEq(vault.balanceOf(user2), sharesUser2 - half);
// 确认用户账户资产增加
        assertEq(user2Token0After, user2Token0Before + (address(token0) == address(weth) ? amountWeth : amountUsdc));
        assertEq(user2Token1After, user2Token1Before + (address(token1) == address(weth) ? amountWeth : amountUsdc));

    }

        
// 测试金库处于再平衡中时，用户赎回部分资产
    function test_redeemInRebalance() public {
        usdc.mint(user2, 3000e18);
        weth.mint(user2, 3000e18);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidityUser1, uint256 sharesUser1,,) = vault.deposit(50e18, 50e18, 0, user1);
        assertTrue(liquidityUser1 > 0);
        assertTrue(sharesUser1 > 0);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        (uint128 liquidityUser2, uint256 sharesUser2,,) = vault.deposit(100e18, 100e18, 0, user2);
        assertTrue(liquidityUser2 > 0);
        assertTrue(sharesUser2 > 0);
        vm.stopPrank();

        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());

// 价格跌到旧区间下方，仓位只剩 token0。
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

// 新区间包住现价，但金库没有 token1，铸不出流动性。
        vm.startPrank(admin);
        int24 rebalanceTickLower = -12060;
        int24 rebalanceTickUpper = -12000;
        (uint128 newLiquidity,,) = vault.rebalance(rebalanceTickLower, rebalanceTickUpper);
        vm.stopPrank();

        bytes32 positionKey = keccak256(abi.encodePacked(address(vault), rebalanceTickLower, rebalanceTickUpper));
        (uint128 liquidity,,,,) = pool.positions(positionKey);
        assertEq(newLiquidity, 0);
        assertEq(liquidity, 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertGt(token0.balanceOf(address(vault)), 0);

// 补进 token1，两种闲置余额都大于 0。
        token1.transfer(address(vault), 100e18);
        assertGt(token0.balanceOf(address(vault)), 0);
        assertGt(token1.balanceOf(address(vault)), 0);

        uint256 half = sharesUser2 / 2;
        uint256 denominator = vault.totalSupply() + 10 ** 12;
        (uint256 totalUsdc, uint256 totalWeth) = vault.totalAmount();
        uint256 user2Token0Before = token0.balanceOf(user2);
        uint256 user2Token1Before = token1.balanceOf(user2);


        vm.startPrank(user2);
        (uint256 amountUsdc, uint256 amountWeth) = vault.redeem(half);
        vm.stopPrank();

        // solidity中，uint256的除法会向下取整，所以这里需要使用!=
        if (vault.balanceOf(user2)  != half) {
            assertTrue(vault.balanceOf(user2) >= half);
            assertTrue(vault.balanceOf(user2) == half+1);
        }

        assertEq(amountUsdc, Math.mulDiv(totalUsdc, half, denominator));
        assertEq(amountWeth, Math.mulDiv(totalWeth, half, denominator));
        assertGt(amountUsdc, 0);
        assertGt(amountWeth, 0);
        assertEq(token0.balanceOf(user2), user2Token0Before + (address(token0) == address(weth) ? amountWeth : amountUsdc));
        assertEq(token1.balanceOf(user2), user2Token1Before + (address(token1) == address(weth) ? amountWeth : amountUsdc));
        assertEq(vault.balanceOf(user2), sharesUser2 - half);
    }

        // 测试赎回份额大于拥有的份额
    function test_redeemMoreThanBalanceAndRedeemEqualZero() public {
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
        vault.redeem(redeemAmount);

        vm.expectRevert("Shares must be greater than 0");
        vault.redeem(0);

        vault.redeem(shares/2);

        vm.stopPrank();
    }

    
    // 赎回前算出这次份额应拿到的两种币。
    // 本金、整段手续费、闲置余额各按 shares / (totalSupply + 10^12) 取一份，再按 token0、token1 归位。
    function _expectedRedeem(uint256 shares) internal returns (uint256 expectedUsdc, uint256 expectedWeth) {
        uint256 denominator = vault.totalSupply() + 10 ** 12;
        bytes32 positionKey = keccak256(abi.encodePacked(address(vault), vault.tickLower(), vault.tickUpper()));
        (uint256 amount0, uint256 amount1) = _principal(positionKey, shares, denominator);
        (uint256 fee0, uint256 fee1) = _fees(positionKey, shares, denominator);
        uint256 idle0 = Math.mulDiv(IERC20(pool.token0()).balanceOf(address(vault)), shares, denominator);
        uint256 idle1 = Math.mulDiv(IERC20(pool.token1()).balanceOf(address(vault)), shares, denominator);
        bool usdcIsToken0 = address(usdc) == pool.token0();
        expectedUsdc = usdcIsToken0 ? amount0 + fee0 + idle0 : amount1 + fee1 + idle1;
        expectedWeth = usdcIsToken0 ? amount1 + fee1 + idle1 : amount0 + fee0 + idle0;
    }

    // shares份份额对应的流动性，按现价换成 token0、token1。取整向下，和池子 burn 退回本金的方向一致。
    function _principal(bytes32 positionKey, uint256 shares, uint256 denominator)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint128 liquidity,,,,) = pool.positions(positionKey);
        uint128 liquidityShare = uint128(Math.mulDiv(liquidity, shares, denominator));
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        int24 tickLower = vault.tickLower();
        int24 tickUpper = vault.tickUpper();
        amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickUpper), liquidityShare, false);
        amount1 = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(tickLower), sqrtPriceX96, liquidityShare, false);
    }


    // 整段仓位未领取的手续费，再乘上这次份额的比例。手续费按全部流动性结算。
    function _fees(bytes32 positionKey, uint256 shares, uint256 denominator) internal returns (uint256 fee0, uint256 fee1) {
        (
            uint128 liquidityBefore,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(positionKey);
        (, int24 tick,,,,,) = pool.slot0();
        (uint256 feeGrowthInside0Now, uint256 feeGrowthInside1Now) = getFee(vault.tickLower(), vault.tickUpper(), tick);
        fee0 = Math.mulDiv(feeGrowthInside0Now - feeGrowthInside0Last, liquidityBefore, 1 << 128) + tokensOwed0;
        fee1 = Math.mulDiv(feeGrowthInside1Now - feeGrowthInside1Last, liquidityBefore, 1 << 128) + tokensOwed1;
        fee0 = Math.mulDiv(fee0, shares, denominator);
        fee1 = Math.mulDiv(fee1, shares, denominator);
    }

    // 当前区间内每单位流动性累计的手续费。全局累计减去区间下方和上方的两段，不是 feeGrowthGlobal 本身。
    function getFee(int24 tickLower, int24 tickUpper, int24 tick) public
    returns (uint256 feeGrowthInside0Now, uint256 feeGrowthInside1Now) 
    {
        require(tickLower < tickUpper, "tickLower must be less than tickUpper");
        require(tick >= tickLower && tick < tickUpper, "tick must be between tickLower and tickUpper");
        (,, uint256 feeGrowthOutside0Lower, uint256 feeGrowthOutside1Lower,,,,) = pool.ticks(tickLower);
        (,, uint256 feeGrowthOutside0Upper, uint256 feeGrowthOutside1Upper,,,,) = pool.ticks(tickUpper);
        uint256 feeGrowthGlobal0 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1 = pool.feeGrowthGlobal1X128();

        uint256 feeGrowthBelow0 = tick >= tickLower? feeGrowthOutside0Lower: feeGrowthGlobal0 - feeGrowthOutside0Lower;
        uint256 feeGrowthAbove0 = tick < tickUpper? feeGrowthOutside0Upper: feeGrowthGlobal0 - feeGrowthOutside0Upper;
        uint256 feeGrowthInside0Now = feeGrowthGlobal0 - feeGrowthBelow0 - feeGrowthAbove0;

        uint256 feeGrowthBelow1 = tick >= tickLower? feeGrowthOutside1Lower: feeGrowthGlobal1 - feeGrowthOutside1Lower;
        uint256 feeGrowthAbove1 = tick < tickUpper? feeGrowthOutside1Upper: feeGrowthGlobal1 - feeGrowthOutside1Upper;
        uint256 feeGrowthInside1Now = feeGrowthGlobal1 - feeGrowthBelow1 - feeGrowthAbove1;
        return (feeGrowthInside0Now, feeGrowthInside1Now); 
    }


}