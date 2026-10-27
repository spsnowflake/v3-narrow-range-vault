// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";

// 测试金库 admin 相关的方法
contract VaultAdminTest is VaultFixture {

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address admin = makeAddr("admin");


    function test_changeAdmin() public {
        vm.startPrank(admin);
        vault.changeAdmin(user1);
        assertEq(vault.admin(), user1);
    }
 
    function test_changeAdminFail() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes("Only admin can change admin"));
        vault.changeAdmin(user1);
    }


}

