// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "uniswap-v3-core/contracts/libraries/TickMath.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";
import {TestERC20} from "../utils/TestERC20.sol";

/// 公开函数只有 deposit、redeem、rebalance。铸币和授权写在 deposit 里面。 
contract VaultInvariantBase is StdUtils {
    // 没有继承Test，这里需要手动获取 Foundry 作弊码接口。
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    V3NarrowRangeVault public vault;
    TestERC20 public usdc;
    TestERC20 public weth;
    IUniswapV3Pool public pool;
    address public admin;

    // 份额只会铸给这几个地址，后面才能把它们的余额加总后和 totalSupply 比较。
    address[] public users;

    // 只有管理员的再平衡成功后才更新。
    int24 public expectedLower;
    int24 public expectedUpper;

    constructor(
        V3NarrowRangeVault vault_,
        TestERC20 usdc_,
        TestERC20 weth_,
        IUniswapV3Pool pool_,
        address admin_
    ) {
        vault = vault_;
        usdc = usdc_;
        weth = weth_;
        pool = pool_;
        admin = admin_;
        expectedLower = vault.tickLower();
        expectedUpper = vault.tickUpper();

// 准备3个固定用户
        users.push(address(uint160(0xA1)));
        users.push(address(uint160(0xA2)));
        users.push(address(uint160(0xA3)));
    }

    function actorCount() external view returns (uint256) {
        return users.length;
    }

    /// 随机选一个用户，铸两种币、授权，再存款。数量收在能铸出流动性的范围内。
    function deposit(uint256 userSeed, uint256 usdcAmount, uint256 wethAmount) external {
        // userSeed 是 Foundry 给的随机数
        address user = users[userSeed % users.length];
        usdcAmount = bound(usdcAmount, 1e16, 1e21);
        wethAmount = bound(wethAmount, 1e16, 1e21);
    // 铸币、授权且存款
        usdc.mint(user, usdcAmount);
        weth.mint(user, wethAmount);

        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(usdcAmount, wethAmount, 0, user);
        vm.stopPrank();
    }

    function redeem(uint256 userSeed, uint256 shares) external {
    // 这个用户还没有份额时直接返回。
        address user = users[userSeed % users.length];
        uint256 balanceOfUser = vault.balanceOf(user);
        if (balanceOfUser == 0) return;

        shares = bound(shares, 1, balanceOfUser);
        vm.prank(user);
        vault.redeem(shares);
    }

    /// 新区间随机，但收成 tick 间距的倍数，并且包住均价 0。
    /// 一半次数用管理员调用，另一半用普通用户。普通用户的回滚catch接住。
    function rebalance(uint256 callerSeed, int24 newTickLower, int24 newTickUpper) external {
        int24 spacing = pool.tickSpacing();
        newTickLower = int24(bound(newTickLower, -12000, 0));
        newTickUpper = int24(bound(newTickUpper, 1, 12000));
        // 向更小的间距倍数取整
        newTickLower = _floorToSpacing(newTickLower, spacing);
        newTickUpper = (newTickUpper / spacing) * spacing;
        // 1 到 59 收成间距后是 0。均价是 0，上沿必须大于 0。
        if (newTickUpper <= 0) newTickUpper = spacing;
        // 一半次数用管理员调用，另一半用普通用户。
        if (callerSeed % 2 == 0) {
            vm.prank(admin);
            try vault.rebalance(newTickLower, newTickUpper) {
                expectedLower = vault.tickLower();
                expectedUpper = vault.tickUpper();
            } catch {}
        } else {
            vm.prank(users[callerSeed % users.length]);
            try vault.rebalance(newTickLower, newTickUpper) {} catch {}
        }
    }

    /// 负数除法向 0 取整，这里改成向更小的间距倍数取整。
    // -61 / 60 得到 -1，再乘 60 是 -60。-61 实际该落到更小的 -120
    function _floorToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 steps = tick / spacing;
        if (tick < 0 && tick % spacing != 0) steps -= 1;
        return steps * spacing;
    }
}
