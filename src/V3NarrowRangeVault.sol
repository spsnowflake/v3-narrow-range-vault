// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {TickMath} from "uniswap-v3-core/contracts/libraries/TickMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SqrtPriceMath} from "uniswap-v3-core/contracts/libraries/SqrtPriceMath.sol";
import {FullMath} from "uniswap-v3-core/contracts/libraries/FullMath.sol";
import {Tick} from "uniswap-v3-core/contracts/libraries/Tick.sol";

contract V3NarrowRangeVault is ERC4626 {

    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    IERC20 public usdc_erc20;
    IERC20 public weth_erc20;
    IUniswapV3Pool public pool;
    int24 public tickLower;
    int24 public tickUpper;


    constructor(IUniswapV3Pool pool_, IERC20 asset_,int24 tickLower_, int24 tickUpper_)
        ERC20("V3_Narrow_Range_Vaul","v3nrv")
        ERC4626(asset_)
    {
 
        address token0Address = pool_.token0();
        address token1Address = pool_.token1();

        if (address(asset_) != token0Address && address(asset_) != token1Address) {
            revert();
        }
        if (token0Address == address(asset_)) {
            usdc_erc20 = IERC20(token0Address);
            weth_erc20 = IERC20(token1Address);
        } else {
            usdc_erc20 = IERC20(token1Address);
            weth_erc20 = IERC20(token0Address);
        }
        pool = pool_;
        tickLower = tickLower_;
        tickUpper = tickUpper_;
    }


// 返回当前池子中持有的资产价值，以USDC计价。
    function totalAssets() public view override returns (uint256) {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(positionKey);

        (uint160 sqrtPriceX96, int24 tick, , ,,,) = pool.slot0();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // 仓位中持有的token0和token1数量
        uint256 amount0;
        uint256 amount1;

        if(liquidity != 0){
            if (tick < tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, false);
            } else if (tick < tickUpper) {
                amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, liquidity, false);
                amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, liquidity, false);
            } else {
                amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, false);
            }
        }

        // 计算区间内自上次更新以来的手续费
        (,, uint256 feeGrowthOutside0Lower, uint256 feeGrowthOutside1Lower,,,,) = pool.ticks(tickLower);
        (,, uint256 feeGrowthOutside0Upper, uint256 feeGrowthOutside1Upper,,,,) = pool.ticks(tickUpper);
        uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();

// 0.8版本溢出会回滚。这里即便溢出一次，计算也不会出错。
        unchecked {
            uint256 feeGrowthBelow0X128 = tick >= tickLower
                ? feeGrowthOutside0Lower
                : feeGrowthGlobal0X128 - feeGrowthOutside0Lower;

            uint256 feeGrowthAbove0X128 = tick < tickUpper
                ? feeGrowthOutside0Upper
                : feeGrowthGlobal0X128 - feeGrowthOutside0Upper;
            uint256 feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;

            uint256 feeGrowthBelow1X128 = tick >= tickLower
                ? feeGrowthOutside1Lower
                : feeGrowthGlobal1X128 - feeGrowthOutside1Lower;
            uint256 feeGrowthAbove1X128 = tick < tickUpper
                ? feeGrowthOutside1Upper
                : feeGrowthGlobal1X128 - feeGrowthOutside1Upper;
            uint256 feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;

            // 计算未领取的手续费
            tokensOwed0 += uint128(FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity,Q128));
            tokensOwed1 += uint128(FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity,Q128));
        }

        // 计算token0和1的总数量
        uint256 totalUsdc = address(usdc_erc20)==pool.token0()? 
        amount0 + tokensOwed0 + IERC20(usdc_erc20).balanceOf(address(this)):
        amount1 + tokensOwed1 + IERC20(usdc_erc20).balanceOf(address(this));

        uint256 totalWeth = address(weth_erc20)==pool.token1()? 
        amount1 + tokensOwed1 + IERC20(weth_erc20).balanceOf(address(this)):
        amount0 + tokensOwed0 + IERC20(weth_erc20).balanceOf(address(this));

        // 计算资产价值。求出来的是总的 eth+usdc 的价值，eth 先折价为 usdc。
        return totalWeth / getPrice()  + totalUsdc;
    }


// 返回价格（1E值多少U）
    function getETHAsUSDCPrice() public view returns (uint256) {
        // 1 个 WETH 值多少 USDC = 10^18 / price / 10^6 = 10^12 / price
        return 10**12/getPrice();
    }

    function getPrice() public view returns (uint256) {
        // 查询池子最近1800秒的累计tick
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 1800;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);

        // 计算累计tick的差值
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        // 计算平均tick。delta为负数时，除法取整靠近0，要向负无穷取整，所以需要减1
        int24 averageTick = int24(delta % 1800 != 0&&delta<0 ? (delta / 1800) - 1 : (delta / 1800));
        
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        // token1/token0（E/U）的价格
        return Math.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 192);
    }


    
}



