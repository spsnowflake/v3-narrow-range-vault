// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {VaultFixture} from "../utils/VaultFixture.sol";


// 测试重入
contract ReentrancyTest is VaultFixture {
    address user1 = makeAddr("user1");

    function test_reentrancy() public {
        ReenteringERC20 usdcToken = new ReenteringERC20("USD Coin", "USDC", 6);
        TestERC20 wethToken = new TestERC20("Wrapped Ether", "WETH", 18);
        pool = IUniswapV3Pool(factory.createPool(address(usdcToken), address(wethToken), POOL_FEE));
        pool.initialize(INIT_SQRT_PRICE_X96);
        pool.increaseObservationCardinalityNext(2);
        vm.warp(block.timestamp + 1800);

        vault = new V3NarrowRangeVault(pool, IERC20(address(usdcToken)), TICK_LOWER, TICK_UPPER);
        usdcToken.setVault(vault);
        usdcToken.enableAttack();

        usdcToken.mint(user1, 3000e18);
        wethToken.mint(user1, 3000e18);
        vm.startPrank(user1);
        usdcToken.approve(address(vault), type(uint256).max);
        wethToken.approve(address(vault), type(uint256).max);

        (uint128 liquidity,,, uint256 shares) = vault.deposit(1000, 1000, 0, user1);
        vm.stopPrank();

        // 回调里的第二次 deposit 被池子锁回滚，外层只铸了一次份额。
        // 如果attacked为true，说明第二次调用（重入）执行了
        assertTrue(usdcToken.attacked());
        // 重入失败
        assertFalse(usdcToken.innerSucceeded());
        // 池子被锁住了执行了回滚，回滚原因
        assertEq(usdcToken.revertData(), abi.encodeWithSignature("Error(string)", "LOK"));
        // 只有一次调用的份额
        assertTrue(liquidity > 0);
        assertTrue(shares > 0);
        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.getLiquidity(), liquidity);
    }
}

// 新部署一个代币u，transferFrom 中多了一步，第一次被调用时，先去调用金库的 deposit。
/// 转账时再调用一次 deposit。池子正在 mint，里面这次会撞上锁。
contract ReenteringERC20 is ERC20 {
    uint8 private immutable _tokenDecimals;
    V3NarrowRangeVault public vault;
    bool public attack;
    bool public attacked;
    bool public innerSucceeded;
    bytes public revertData;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setVault(V3NarrowRangeVault vault_) external {
        vault = vault_;
    }

    function enableAttack() external {
        attack = true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (attack && !attacked) {
            attacked = true;
            try vault.deposit(1000, 1000, 0, from) {
                innerSucceeded = true;

                // 如果池子锁了，以LOK回滚，回滚记在revertData里。
                // catch接住回滚，函数就不会停止。
            } catch (bytes memory reason) {
                revertData = reason;
            }
        }
        return super.transferFrom(from, to, value);
    }
}


