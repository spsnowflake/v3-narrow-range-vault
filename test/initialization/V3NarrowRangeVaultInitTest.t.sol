// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";

//  测试 V3NarrowRangeVault 构造函数初始化
contract V3NarrowRangeVaultInit is VaultFixture {
    function test_constructorInitialized() public view {
        assertEq(usdc.decimals(), 6);
        assertEq(weth.decimals(), 18);

        address token0 = pool.token0();
        address token1 = pool.token1();
        assertTrue(token0 == address(usdc) || token0 == address(weth));
        assertTrue(token1 == address(usdc) || token1 == address(weth));
        assertTrue(token0 < token1);

        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        assertEq(sqrtPriceX96, INIT_SQRT_PRICE_X96);
        assertEq(tick, 0);
        assertEq(pool.tickSpacing(), TICK_SPACING);

        assertEq(address(vault.pool()), address(pool));
        assertEq(address(vault.usdc_erc20()), address(usdc));
        assertEq(address(vault.weth_erc20()), address(weth));
        assertEq(vault.tickLower(), TICK_LOWER);
        assertEq(vault.tickUpper(), TICK_UPPER);
        assertEq(vault.admin(), address(this));

        // tick 0 上，两种币的原始比价是 1，和谁是 token0 无关。
        assertEq(vault.getPrice(), 1);
    }


// 测试金库资产为池子的token0时，构造函数会成功。（让 usdc 为 token0）
    function test_constructorAssetToken0() public {
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

        assertEq(pool.token0(), address(usdcToken));
        assertEq(pool.token1(), address(wethToken));

        assertEq(address(vault.usdc_erc20()), address(pool.token0()));
        assertEq(address(vault.weth_erc20()), address(pool.token1()));
    }


// 测试金库资产为weth时，构造函数会 revert
    function test_constructorAssetToken0Fail() public {
        vm.expectRevert(bytes("Asset decimals must be 6"));
        vault = new V3NarrowRangeVault(pool, weth, TICK_LOWER, TICK_UPPER);
    }

// 测试金库资产为usdc时，构造函数会成功
    function test_constructorAssetToken1() public {
        vault = new V3NarrowRangeVault(pool, usdc, TICK_LOWER, TICK_UPPER);
        assertEq(address(vault.usdc_erc20()), address(usdc));
        assertEq(address(vault.weth_erc20()), address(weth));
    }

// 测试池子另外一个 token 的 decimals 不是 18 时，构造函数会 revert
    function test_constructorOtherTokenDecimalsNot18() public {
        usdc = new TestERC20("USD Coin", "USDC", 6);
        TestERC20 weth2 = new TestERC20("Wrapped Ether2", "WETH2", 17);

        factory = IUniswapV3Factory(_deployFactory());
        pool = IUniswapV3Pool(factory.createPool(address(usdc), address(weth2), POOL_FEE));
        pool.initialize(INIT_SQRT_PRICE_X96);
        vm.expectRevert(bytes("Other token decimals must be 18"));
        vault = new V3NarrowRangeVault(pool, usdc, TICK_LOWER, TICK_UPPER);
    }

// 测试资产不属于token0 或 token1时，构造函数会 revert
    function test_constructorAssetRevert() public {
        TestERC20 usdt = new TestERC20("USDT", "USDT", 6);
        vm.expectRevert(bytes("Asset not in the pool's token pair"));
        vault = new V3NarrowRangeVault(pool, usdt, TICK_LOWER, TICK_UPPER);
    }

}
