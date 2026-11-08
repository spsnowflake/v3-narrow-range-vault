// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {V3NarrowRangeVault} from "../../src/V3NarrowRangeVault.sol";


contract ForkTest is Test {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    address public user = makeAddr("user");
    address public admin = makeAddr("admin");
    ERC20 public usdc;
    ERC20 public weth;
    IUniswapV3Pool public pool;
    int24 public _tickLower;
    int24 public _tickUpper;
    V3NarrowRangeVault public vault;

    uint256 internal constant FORK_BLOCK = 0x1926310;

    function setUp() public {
        // 连接到主网
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), FORK_BLOCK);
        usdc = ERC20(USDC);
        weth = ERC20(WETH);
        pool = IUniswapV3Pool(POOL);
        deal(address(usdc), user, 100000e6);
        deal(address(weth), user, 100 ether);

        // 0.3% 池的 tickSpacing 是 60。先把现价收到最近的间距倍数，再各扩一档，区间就是现价两侧各 60。
        int24 spacing = pool.tickSpacing();
        (, int24 tick, , , , , ) = pool.slot0();
        int24 center = _roundToSpacing(tick, spacing);
        _tickLower = center - spacing;
        _tickUpper = center + spacing;

        assertTrue(_tickLower < tick && tick < _tickUpper);
        assertEq(_tickLower % spacing, 0);
        assertEq(_tickUpper % spacing, 0);
        assertEq(int256(_tickUpper - _tickLower), int256(spacing) * 2);
        vm.prank(admin);
        vault = new V3NarrowRangeVault(pool, usdc, _tickLower, _tickUpper);
    }


    function testFork() public {
        // 存一笔
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        weth.approve(address(vault), type(uint256).max);
        uint256 usdcUserBalanceBefore = usdc.balanceOf(user);
        uint256 wethUserBalanceBefore = weth.balanceOf(user);
        (uint128 liquidity,uint256 usdcCount,uint256 wethCount,uint256 shares) = vault.deposit(10000e6, 10 ether, 0, user);
        vm.stopPrank();
        assertEq(usdc.balanceOf(user), usdcUserBalanceBefore - usdcCount);
        assertEq(weth.balanceOf(user), wethUserBalanceBefore - wethCount);
        assertEq(vault.balanceOf(user), shares);
        assertTrue(liquidity > 0);
        assertTrue(usdcCount > 0 && usdcCount <= 10000e6);
        assertTrue(wethCount > 0 && wethCount <= 10 ether);
        assertTrue(shares > 0);
        // 测试份额正确
        uint256 assets = vault.wethInUsdc(wethCount) + usdcCount;
        uint256 shares2 = assets * 10**12 / (vault.totalAssets() + 1);
        assertEq(shares2, shares);

        // 测试赎回一半
        uint256 usdcUserBalanceRedeemBefore = usdc.balanceOf(user);
        uint256 wethUserBalanceRedeemBefore = weth.balanceOf(user);
        vm.startPrank(user);
        (uint256 usdcOut, uint256 wethOut) = vault.redeem(shares / 2);
        vm.stopPrank();
// 赎回金额回到用户手中
        assertEq(usdc.balanceOf(user), usdcUserBalanceRedeemBefore + usdcOut);
        assertEq(weth.balanceOf(user), wethUserBalanceRedeemBefore + wethOut);
        // 测试份额确实烧掉
        assertEq(vault.balanceOf(user), shares - (shares / 2));
        uint128 liquidityAfter = vault.getLiquidity();
        // 测试赎回后，流动性不为0
        assertTrue(liquidityAfter < liquidity && liquidityAfter > 0);

        // 再平衡
        vm.startPrank(admin);
        int24 spacing = pool.tickSpacing();
        (, int24 tick, , , , , ) = pool.slot0();
        int24 center = _roundToSpacing(tick, spacing);
        (uint128 liquidityRebalance, , ) = vault.rebalance(center - spacing*2, center + spacing*2);
        vm.stopPrank();
// 新仓位流动性大于0，且新的上下沿写进金库
        assertTrue(vault.getLiquidity() >0 && vault.getLiquidity() == liquidityRebalance);
        assertEq(vault.tickLower(), center - spacing*2);
        assertEq(vault.tickUpper(), center + spacing*2);
        // 确认新区间和旧区间不同
        assertTrue(vault.tickLower() != _tickLower || vault.tickUpper() != _tickUpper);

// 旧仓位流动性为0
        bytes32 positionKey = keccak256(abi.encodePacked(address(vault), _tickLower, _tickUpper));
        (uint128 originalLiquidity, , , , ) = pool.positions(positionKey);
        assertEq(originalLiquidity,0);
    }

    /// 收到离 tick 最近的间距倍数，使现价落在正负一档的正中。
    function _roundToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 floorTick = _floorToSpacing(tick, spacing);
        int24 remainder = tick - floorTick;
        // 高出的部分有没有达到半档(30).小于半档离下面那档更近.
        // 尽量的让现价处于正中
        if (remainder * 2 >= spacing) return floorTick + spacing;
        return floorTick;
    }

    /// 负数除法向 0 取整，这里改成向更小的间距倍数取整。
    function _floorToSpacing(int24 tick, int24 spacing) private pure returns (int24) {
        int24 steps = tick / spacing;
        if (tick < 0 && tick % spacing != 0) steps -= 1;
        return steps * spacing;
    }
}