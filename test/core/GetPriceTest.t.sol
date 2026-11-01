// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {VaultFixture} from "../utils/VaultFixture.sol";
import {TickMath} from "../../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract GetPriceAndGetETHAsUSDCPriceTest is VaultFixture {


// 测试 token0 是 usdc时，getPirce走的分支。
    function test_usdcToken0UsesMulDiv() public {
    // 测试构建的 pool 中的 token0 是 weth，主网是usdc，这里通过 create2 让测试里 token0是usdc
        bytes memory usdcInit = abi.encodePacked(type(TestERC20).creationCode, abi.encode("USD Coin", "USDC", uint8(6)));
        bytes memory wethInit = abi.encodePacked(type(TestERC20).creationCode, abi.encode("Wrapped Ether", "WETH", uint8(18)));
        TestERC20 usdcToken;
        TestERC20 wethToken;
        for (uint256 salt = 0; salt < 1000; salt++) {
            address usdcAddr = vm.computeCreate2Address(bytes32(salt), keccak256(usdcInit), address(this));
            address wethAddr = vm.computeCreate2Address(bytes32(salt + 1000), keccak256(wethInit), address(this));
            if (usdcAddr < wethAddr) {
                usdcToken = new TestERC20{salt: bytes32(salt)}("USD Coin", "USDC", 6);
                wethToken = new TestERC20{salt: bytes32(salt + 1000)}("Wrapped Ether", "WETH", 18);
                // 用这两个地址 createPool、initialize，再把 usdcToken 传进构造函数
                break;
            }
        }
        pool = IUniswapV3Pool(factory.createPool(address(usdcToken), address(wethToken), POOL_FEE));
        pool.initialize(INIT_SQRT_PRICE_X96);
        vault = new V3NarrowRangeVault(pool, IERC20(pool.token0()), TICK_LOWER, TICK_UPPER);

        pool.swap(
            address(this),
            false, // false 价格下跌，方向跟之前几个测试相反
            1,
            TickMath.getSqrtRatioAtTick(6932),
            ""
        );
        vm.warp(block.timestamp + 1800);
        (, int24 tick, , , , , ) = pool.slot0();
        assertEq(tick, 6932);
        assertEq(vault.getPrice(), 2);

    }

// 走的是求平均tick，tick为负数且不能整除，需要-1的路径。
    function test_negativeRemainderRoundsDown() public {
       pool.swap(
            address(this),
            true, // true 价格下跌，tick 变小
            1,
            TickMath.getSqrtRatioAtTick(-6935),
            ""
        );
        vm.warp(block.timestamp + 1799);
        (, int24 tick, , , , , ) = pool.slot0();
        assertEq(tick, -6935);
        assertEq(vault.getPrice(), 2);
    }

// 目前weth是token0，getPrice 返回的是池子价格的倒数；正 tick 会让这个倒数小于 1，整数结果变成 0。
// getPrice = 1 / 1.0001^tick = 1.0001^(-tick)
// 要让这个整数结果是 2，就需要 1.0001^(-tick) ≈ 2，也就是：-tick ≈ ln(2) / ln(1.0001) ≈ 6931.47
    function test_wethToken0UsesInverse() public {
        pool.swap(
            address(this),
            true, // true 价格下跌，tick 变小
            1,
            TickMath.getSqrtRatioAtTick(-6932),
            ""
        );
        vm.warp(block.timestamp + 1800);
        (, int24 tick, , , , , ) = pool.slot0();
        assertEq(tick, -6932);
        assertEq(vault.getPrice(), 2);

    }

// 夹具里面价格已经是 1 且持续了 1800 秒
    function test_tickZeroPriceIsOne() public {
        uint256 price = vault.getPrice();
        assertEq(price, 1);
    }

// 夹具里面价格已经是 1 且持续了 1800 秒
    function test_oneWethIs1e12Usdc() public {
        uint256 price = vault.getETHAsUSDCPrice();
        assertEq(price, 10**12);
    }


    // 空回调，swap需要。
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external {}


}

















