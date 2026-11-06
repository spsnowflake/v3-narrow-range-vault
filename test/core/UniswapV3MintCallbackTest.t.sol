// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



import {VaultFixture} from "../utils/VaultFixture.sol";


contract UniswapV3MintCallbackTest is VaultFixture {
    address user1 = makeAddr("user1");

// 测试uniswapV3MintCallback 方法失败，msg.sender不是池子。
    function test_UniswapV3MintCallback() public {
        vm.startPrank(user1);
        vm.expectRevert("UniswapV3MintCallback: msg.sender must be pool");
        vault.uniswapV3MintCallback(1, 1, abi.encode(user1));
        vm.stopPrank();
    }
}