// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IUniswapV3Pool} from "uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {TickMath} from "uniswap-v3-core/contracts/libraries/TickMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract V3NarrowRangeVault is ERC4626 {

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


// 返回价格（1E值多少U）
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
        uint256 price = Math.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 192);
        // 1 个 WETH 值多少 USDC = 10^18 / price / 10^6 = 10^12 / price
        return 10**12/price;
    }
    
}



