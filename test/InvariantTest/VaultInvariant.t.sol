// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultFixture} from "../utils/VaultFixture.sol";
import {VaultInvariantBase} from "./VaultInvariantBase.sol";

/// 不变量测试。
contract VaultInvariantTest is VaultFixture {
    VaultInvariantBase internal base;

    function setUp() public override {
        // 初始化池子和金库。
        super.setUp();

        base = new VaultInvariantBase(vault, usdc, weth, pool, makeAddr("admin"));

        // 只随机调用处理合约上的这三个函数
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = base.deposit.selector;
        selectors[1] = base.redeem.selector;
        selectors[2] = base.rebalance.selector;


        // 指定被随机调用的合约是 VaultInvariantBase
        targetContract(address(base));

        // targetSelector 把范围收成指定合约上的三个函数：deposit、redeem、rebalance
        targetSelector(FuzzSelector({addr: address(base), selectors: selectors}));

        // VaultInvariantTest 继承了 Test，上面有很多公开函数。
        // 排除掉测试合约自己的公开函数，避免 Foundry 把检查函数当成操作去调用。
        excludeContract(address(this));
    }

    /// 所有用户手里的份额加起来，必须等于金库的 totalSupply。
    function invariant_shareSumEqualsTotalSupply() public view {
        uint256 sum;
        uint256 count = base.actorCount();
        for (uint256 i = 0; i < count; i++) {
            sum += vault.balanceOf(base.users(i));
        }
        assertEq(sum, vault.totalSupply());
    }

    /// 区间始终包住均价 0，并且两边都是 tick 间距的整数倍。
    function invariant_rangeStaysValid() public view {
        int24 lower = vault.tickLower();
        int24 upper = vault.tickUpper();
        int24 spacing = pool.tickSpacing();

        assertTrue(lower < upper);
        assertEq(lower % spacing, 0);
        assertEq(upper % spacing, 0);
        assertTrue(lower <= int24(0));
        assertTrue(upper > int24(0));
    }

    /// 不是管理员的再平衡被接住之后，区间必须还停在上一次成功的位置。
    function invariant_onlyAdminMovesRange() public view {
        assertEq(vault.tickLower(), base.expectedLower());
        assertEq(vault.tickUpper(), base.expectedUpper());
    }
}
