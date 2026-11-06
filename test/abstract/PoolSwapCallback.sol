// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";

abstract contract PoolSwapCallback is VaultFixture {

    // swap回调
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(pool));
        if (amount0Delta > 0) weth.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) usdc.transfer(msg.sender, uint256(amount1Delta));
    }
}