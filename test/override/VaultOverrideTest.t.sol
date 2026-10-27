// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";

// V3NarrowRangeVault 金库重写 ERC4626 方法，测试重写后是否正确。
contract VaultOverrideTest is VaultFixture {


    function test_deposit() public {
        vm.expectRevert(bytes(""));
        vault.deposit(100, msg.sender);
    }

    function test_mint() public {
        vm.expectRevert(bytes(""));
        vault.mint(100, msg.sender);
    }

    function test_withdraw() public {
        vm.expectRevert(bytes(""));
        vault.withdraw(100, msg.sender, address(this));
    }

    function test_redeem() public {
        vm.expectRevert(bytes(""));
        vault.redeem(100, msg.sender, address(this));
    }
    

    function test_previewDeposit() public {
        vm.expectRevert(bytes(""));
        vault.previewDeposit(100);
    }

     function test_previewMint() public {
        vm.expectRevert(bytes(""));
        vault.previewMint(0);
    }

    function test_previewRedeem() public {
        vm.expectRevert(bytes(""));
        vault.previewRedeem(0);
    }

    function test_previewWithdraw() public {
        vm.expectRevert(bytes(""));
        vault.previewWithdraw(0);
    }

    function test_maxWithdraw() public {
        assertEq(vault.maxWithdraw(msg.sender), 0);
    }

    function test_maxDeposit() public {
        assertEq(vault.maxDeposit(msg.sender), 0);
    }

    function test_maxMint() public {
        assertEq(vault.maxMint(msg.sender), 0);
    }


}