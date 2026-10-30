// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";


// 测试 getLiquidity 函数
contract GetLiquidityTest is VaultFixture {
    address user1 = makeAddr("user1");

    function allow() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 3000e18);
        weth.approve(address(vault), 3000e18);
        vm.stopPrank();
    }

    function test_getLiquidity() public {
        allow();
        vm.startPrank(user1);
        uint128 liquidityTotal = vault.getLiquidity();
        assertEq(liquidityTotal, 0);
        uint128 liquidity1;
        uint128 liquidity2;
        
        (liquidity1, , , ) = vault.deposit(3000e18,5e18, 1e10, address(vault));
        liquidityTotal = vault.getLiquidity();
        assertEq(liquidityTotal, liquidity1);

        (liquidity2, , , ) = vault.deposit(30000e18,10e18, 1e10, address(vault));
        liquidityTotal = vault.getLiquidity();
        assertEq(liquidityTotal, liquidity1 + liquidity2);

    }
}