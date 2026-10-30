// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {TestERC20} from "./TestERC20.sol";

/// 本地池子和金库的共用夹具。后面的测试合约继承它，setUp 会自动执行。
abstract contract VaultFixture is Test {
    uint24 internal constant POOL_FEE = 3000;
    int24 internal constant TICK_SPACING = 60;
    // 2^96。池子原始价格 token1/token0 = 1，对应 tick 0。这不是「1 ETH = 1 USDC」。
    uint160 internal constant INIT_SQRT_PRICE_X96 = 79228162514264337593543950336;
    int24 internal constant TICK_LOWER = -60;
    int24 internal constant TICK_UPPER = 60;

    TestERC20 internal usdc;
    TestERC20 internal weth;
    IUniswapV3Factory internal factory;
    IUniswapV3Pool internal pool;
    V3NarrowRangeVault internal vault;


    function setUp() public virtual {
        usdc = new TestERC20("USD Coin", "USDC", 6);
        weth = new TestERC20("Wrapped Ether", "WETH", 18);

        factory = IUniswapV3Factory(_deployFactory());
        pool = IUniswapV3Pool(factory.createPool(address(usdc), address(weth), POOL_FEE));
        pool.initialize(INIT_SQRT_PRICE_X96);

        // 初始化写下的观察点，要至少早于调用 1800 秒，getPrice 和 rebalance 里的 observe 才能用。
        vm.warp(block.timestamp + 1800);
        // 增加观察点，否则 getPrice 和 rebalance 里的 observe 会失败。
        pool.increaseObservationCardinalityNext(2); 
        
        address admin = makeAddr("admin");
        address user1 = makeAddr("user1");

        usdc.mint(user1, 3000e18);
        weth.mint(user1, 3000e18);

        vm.prank(admin);
        vault = new V3NarrowRangeVault(pool, usdc, TICK_LOWER, TICK_UPPER);
    }

    // 字节码来自 FOUNDRY_PROFILE=factory forge build。0.8 测试不能 new 0.7.6 的工厂。
    function _deployFactory() internal returns (address deployed) {
        bytes memory bytecode = vm.readFileBinary("test/utils/UniswapV3Factory.bin");
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "factory deploy failed");
    }
}
