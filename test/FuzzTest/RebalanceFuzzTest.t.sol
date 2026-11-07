// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {PoolSwapCallback} from "../abstract/PoolSwapCallback.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";




contract RebalanceFuzzTest is VaultFixture, PoolSwapCallback {

    address user1 = makeAddr("user1");
    address admin = makeAddr("admin");


    function testFuzz_rebalance(int24 newTickLower, int24 newTickUpper) public  {
        usdc.mint(user1, 300000e18);
        weth.mint(user1, 300000e18);
        int24 spacing = pool.tickSpacing();
        newTickLower = int24(bound(newTickLower, TickMath.MIN_TICK, 0));
        newTickUpper = int24(bound(newTickUpper, 1, TickMath.MAX_TICK));
        // 确定是spacing的倍数
        newTickLower = (newTickLower / spacing) * spacing;
        newTickUpper = (newTickUpper / spacing) * spacing;
        // 1 到 59 /60 都=0，这里收缩至60
        if (newTickUpper <= 0) newTickUpper = spacing;

        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);

        assertEq(vault.balanceOf(user1), 0);
        (uint128 liquidity, , , uint256 shares) = vault.deposit(300000e18, 300000e18, 0, user1);
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        vm.stopPrank();

        int24 tickLowerBefore = vault.tickLower();
        int24 tickUpperBefore = vault.tickUpper();


// 新区间能保住交易平均tick
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 1800;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);

        // 计算累计tick的差值
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        // 计算平均tick。delta为负数时，除法取整靠近0，要向负无穷取整，所以需要减1
        int24 averageTick = int24(delta % 1800 != 0&&delta<0 ? (delta / 1800) - 1 : (delta / 1800));
        assertTrue(averageTick >= newTickLower && averageTick < newTickUpper);

        vm.startPrank(admin);
        (uint128 newLiquidity, , ) = vault.rebalance(newTickLower, newTickUpper);
        vm.stopPrank();
        assertEq(vault.tickLower(), newTickLower);
        assertEq(vault.tickUpper(), newTickUpper);
        assertTrue(newLiquidity > 0);


        if(tickLowerBefore!=newTickLower || tickUpperBefore!=newTickUpper){
            // 旧仓位流动性为0
            bytes32 positionKey = keccak256(abi.encodePacked(address(vault), tickLowerBefore, tickUpperBefore));
            (liquidity, , , , ) = pool.positions(positionKey);
            assertTrue(liquidity == 0);
        }




    }
}