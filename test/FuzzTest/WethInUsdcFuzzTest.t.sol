// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";


contract WethInUsdcAndGetETHAsUSDCPriceFuzzTest is VaultFixture {
    function testFuzz_wethInUsdc(uint256 wethAmount) public view {
        assertEq(vault.wethInUsdc(wethAmount), wethAmount);
        assertEq(vault.getETHAsUSDCPrice(wethAmount), wethAmount / 1e6);

    }

}