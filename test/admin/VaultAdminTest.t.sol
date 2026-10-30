// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";

// 测试金库 admin 相关的方法
contract VaultAdminTest is VaultFixture {

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address admin = makeAddr("admin");


// 测试 新 admin 不能为 0 address
    function test_newAdminCannotBeZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(bytes("New admin cannot be the zero address"));
        vault.changeAdmin(address(0));
        assertEq(vault.admin(), admin);

    }

// 测试 新 admin 可以调用 changeAdmin 方法
    function test_newAdminCanChange() public {
        vm.prank(admin);
        vault.changeAdmin(user1);
        assertEq(vault.admin(), user1);

        vm.prank(user1);
        vault.changeAdmin(user2);
        assertEq(vault.admin(), user2);
    }

// 测试 旧 admin 不能调用 changeAdmin 方法
    function test_oldAdminNotChange() public {
        vm.startPrank(admin);
        vault.changeAdmin(user1);

        vm.expectRevert(bytes("Only admin can change admin"));
        vault.changeAdmin(user2);
        assertEq(vault.admin(), user1);
    }

// 测试 admin 可以调用 changeAdmin 方法
    function test_changeAdmin() public {
        vm.startPrank(admin);
        vault.changeAdmin(user1);
        assertEq(vault.admin(), user1);
    }
 
// 测试非 admin 不能调用 changeAdmin 方法
    function test_changeAdminFail() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes("Only admin can change admin"));
        vault.changeAdmin(user1);
    }


}

