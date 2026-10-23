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
import {TransferHelper} from "uniswap-v3-core/contracts/libraries/TransferHelper.sol";

contract V3NarrowRangeVault is ERC4626 {

    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    uint256 internal constant Q96 = 0x1000000000000000000000000;


    IERC20 public usdc_erc20;
    IERC20 public weth_erc20;
    IUniswapV3Pool public pool;
    address public admin;
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
        admin = msg.sender;
    }

// 再平衡。销毁原有仓位，创建新仓位。多余的代币存到金库闲置资产中。
    function rebalance(int24 newTickLower, int24 newTickUpper) 
    public 
    onlyAdmin 
    returns (uint128 newLiquidity,uint256 usdc,uint256 weth)
    {
        require(newTickLower < newTickUpper, "newTickLower must be less than newTickUpper");
        require(newTickLower % pool.tickSpacing() == 0 && newTickUpper % pool.tickSpacing() == 0, "newTickLower and newTickUpper must be divisible by tickSpacing");

// 计算池子最近1800秒的平均tick。再平衡需要价格区间囊括在当前tick内。
// 查询池子最近1800秒的累计tick
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 1800;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);

        // 计算累计tick的差值
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        // 计算平均tick。delta为负数时，除法取整靠近0，要向负无穷取整，所以需要减1
        int24 averageTick = int24(delta % 1800 != 0&&delta<0 ? (delta / 1800) - 1 : (delta / 1800));
        require(averageTick >= newTickLower && averageTick < newTickUpper, "averageTick must be between newTickLower and newTickUpper");

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (uint128 liquidity, , , , ) = pool.positions(positionKey);
        
        if (liquidity != 0) {
            pool.burn( tickLower, tickUpper, liquidity);  
        }

        // 闲置资产和手续费都转到金库中。
        pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

        tickLower = newTickLower;
        tickUpper = newTickUpper;

        uint256 amountUsdc = usdc_erc20.balanceOf(address(this));
        uint256 amountWeth = weth_erc20.balanceOf(address(this));

        (newLiquidity, , ,) = previewDeposit(amountUsdc, amountWeth);

        uint256 amount0 ;
        uint256 amount1;

        // 如果 newLiquidity 为0，则凑不齐新区间要的币。
        if (newLiquidity >0) {
            (amount0, amount1) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            newLiquidity,
            abi.encode(address(this))
        );
        }
        // 如果 newLiquidity 为0，则表示这次没有铸出新仓，币留在金库里，返参都是0。
        // 否则，usdc 和 weth 是实际铸进新仓的数量。
        usdc = address(usdc_erc20) == pool.token0() ? amount0 : amount1;
        weth = address(weth_erc20) == pool.token0() ? amount0 : amount1;
    }


// 按个人份额比例赎回
    function Redeem(uint256 shares) public returns (uint256 amountUsdc,uint256 amountWeth) {
        require(shares > 0, "Shares must be greater than 0");
        require(shares <= balanceOf(msg.sender), "Insufficient balance");

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (uint128 liquidity, , , , ) = pool.positions(positionKey);
        uint256 denominator = totalSupply() + 10 ** _decimalsOffset();

        if (liquidity != 0 ) {
    // 个人份额比例的流动性
            liquidity = toUint128(Math.mulDiv(liquidity, shares, denominator, Math.Rounding.Floor));

            (uint256 amount0, uint256 amount1) = pool.burn( tickLower, tickUpper, liquidity);
            (, , , uint128 tokensOwed0After , uint128 tokensOwed1After) = pool.positions(positionKey);

    // 个人份额比例的手续费
    // tokensOwed0After是 完整手续费+销毁个人比例流动性后的资产，完整手续费乘上个人份额比例才是个人应得的手续费。
            uint256 tokensOwed0 = Math.mulDiv(tokensOwed0After - amount0, shares, denominator, Math.Rounding.Floor);
            uint256 tokensOwed1 = Math.mulDiv(tokensOwed1After - amount1, shares, denominator, Math.Rounding.Floor);


            // 个人份额比例的金库闲置资产。在 collect 之前执行
            uint256 idleUsdc = Math.mulDiv(usdc_erc20.balanceOf(address(this)), shares, denominator, Math.Rounding.Floor);
            uint256 idleWeth = Math.mulDiv(weth_erc20.balanceOf(address(this)), shares, denominator, Math.Rounding.Floor);

            pool.collect(address(this), tickLower, tickUpper, toUint128(tokensOwed0 + amount0), toUint128(tokensOwed1 + amount1));
            
            // 区分币种（手续费+流动性兑换后的资产）
            amountUsdc = address(usdc_erc20) == pool.token0() ? tokensOwed0+amount0 : tokensOwed1+amount1;
            amountWeth = address(weth_erc20) == pool.token0() ? tokensOwed0+amount0 : tokensOwed1+amount1;

            _burn(msg.sender, shares);

            amountUsdc += idleUsdc;
            amountWeth += idleWeth;

            TransferHelper.safeTransfer(address(usdc_erc20), msg.sender, amountUsdc);
            TransferHelper.safeTransfer(address(weth_erc20), msg.sender, amountWeth);
            
    // 如果流动性为0，则处于再平衡中。份额都进到了金库闲置资产中。
        }else{
            // 先全部提取到金库闲置资产中
            pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
            // 个人份额比例的金库闲置资产。
            amountUsdc = Math.mulDiv(usdc_erc20.balanceOf(address(this)), shares, denominator, Math.Rounding.Floor);
            amountWeth = Math.mulDiv(weth_erc20.balanceOf(address(this)), shares, denominator, Math.Rounding.Floor);
            _burn(msg.sender, shares);

            TransferHelper.safeTransfer(address(usdc_erc20), msg.sender, amountUsdc);
            TransferHelper.safeTransfer(address(weth_erc20), msg.sender, amountWeth);
        }
    }
 

// 预估赎回数量
    function previewRedeem(uint256 shares,address owner) public view returns (uint256 amountUsdc,uint256 amountWeth) {
        require(shares <= balanceOf(owner), "Insufficient balance");

        (amountUsdc,amountWeth) = totalAmount();
        return (Math.mulDiv(amountUsdc, shares, totalSupply() + 10 ** _decimalsOffset()),
                Math.mulDiv(amountWeth, shares, totalSupply() + 10 ** _decimalsOffset()));

    }


// 存款
    function deposit(uint256 usdcAmount, uint256 wethAmount, uint256 minShares, address receiver) 
        public 
        returns (uint128 liquidity,uint256 shares,uint256 usdc,uint256 weth) 
    {
        (liquidity, , ,  ) = previewDeposit(usdcAmount, wethAmount);

        (uint256 amount0, uint256 amount1) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity,
            abi.encode(msg.sender)
        );

        usdc = address(usdc_erc20) == pool.token0() ? amount0 : amount1;
        weth = address(weth_erc20) == pool.token0() ? amount0 : amount1;

        require(usdc <= usdcAmount && weth <= wethAmount, 'Price slippage check');

// weth 折算成 usdc 资产计价。
        uint256 totalAssets = weth / getPrice() + usdc;

        shares = convertToShares(totalAssets);
        require(shares >= minShares, 'Minimum shares not met');

        _mint(receiver, shares);
        return (liquidity, shares, usdc, weth);
    }

// 重写 uniswapV3MintCallback 方法，用于处理池子 mint 回调付款
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        require(msg.sender == address(pool));
        address payer = abi.decode(data, (address));
        address token0 = pool.token0();
        address token1 = pool.token1();
        if (payer == address(this)) {
            if (amount0Owed > 0) IERC20(token0).transfer(msg.sender, amount0Owed);
            if (amount1Owed > 0) IERC20(token1).transfer(msg.sender, amount1Owed);
        }else{
            if (amount0Owed > 0) IERC20(token0).transferFrom(payer, msg.sender, amount0Owed);
            if (amount1Owed > 0) IERC20(token1).transferFrom(payer, msg.sender, amount1Owed);
        }
    }


// 预估存款数量
    function previewDeposit(uint256 usdcAmount, uint256 wethAmount) 
        public
        view
        returns(uint128 liquidity, uint256 amountUsdc,uint256 amountWeth, uint256 shares) 
    {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 amount0 = address(usdc_erc20) == pool.token0() ? usdcAmount : wethAmount;
        uint256 amount1 = address(usdc_erc20) == pool.token0() ? wethAmount : usdcAmount;

        liquidity = getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount0,
                amount1
            );

            uint256 amountA;
            uint256 amountB;

        if (liquidity!=0) {
            if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

            if (sqrtPriceX96 <= sqrtRatioAX96) {
                amountA = SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
            }else if (sqrtPriceX96 < sqrtRatioBX96) {
                amountA = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtRatioBX96, liquidity, true);
                amountB = SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtPriceX96, liquidity, true);
            }else {
                amountB = SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96,liquidity, true);
            }
            
        }

        amountUsdc = address(usdc_erc20) == pool.token0() ? amountA : amountB;
        amountWeth = address(weth_erc20) == pool.token0() ? amountA : amountB;
        uint256 totalAssets = amountWeth / getPrice() + amountUsdc;

        shares = _convertToShares(totalAssets, Math.Rounding.Floor);
        return (liquidity, amountUsdc, amountWeth, shares);
    }

    /// 给定 token0、token1 数量以及当前池子价格和 tick 边界价格，计算能得到的最大流动性。
    /// sqrtRatioX96：表示池子当前价格的平方根价格
    /// sqrtRatioAX96：第一个 tick 边界对应的平方根价格
    /// sqrtRatioBX96：第二个 tick 边界对应的平方根价格
    /// amount0：投入的 token0 数量
    /// amount1：投入的 token1 数量
    /// liquidity：能得到的最大流动性
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) public pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);

            // 当前价格落在区间内部时，头寸同时持有两种代币，要分别算出两笔流动性，再取较小的那个。
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            // 取两笔流动性中较小的那个，多出来的那种代币不会被用完。
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }


// 获取当前金库在V3中的流动性
    function getLiquidity() public view returns (uint128 liquidity) {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (liquidity, , , , ) = pool.positions(positionKey);
    }

// 计算总资产数量。V3池子 + 未领取手续费 + 金库闲置代币。
    function totalAmount() public view returns (uint256 totalUsdc, uint256 totalWeth) {
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
            tokensOwed0 += toUint128(FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity,Q128));
            tokensOwed1 += toUint128(FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity,Q128));
        }

        // 计算token0和1的总数量
        totalUsdc = address(usdc_erc20)==pool.token0()? 
        amount0 + tokensOwed0 + IERC20(usdc_erc20).balanceOf(address(this)):
        amount1 + tokensOwed1 + IERC20(usdc_erc20).balanceOf(address(this));

        totalWeth = address(weth_erc20)==pool.token1()? 
        amount1 + tokensOwed1 + IERC20(weth_erc20).balanceOf(address(this)):
        amount0 + tokensOwed0 + IERC20(weth_erc20).balanceOf(address(this));

    }


// 返回当前池子中持有的资产价值，以USDC计价。
    function totalAssets() public view override returns (uint256) {
        (uint256 totalUsdc, uint256 totalWeth) = totalAmount();
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

        // 排序，确保token0是usdc，token1是weth
        if (address(usdc_erc20) == pool.token0()) {
        // token1/token0（E/U）的价格
            return Math.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 192);
        }
        uint256 quote = uint256(sqrtPriceX96);
        return ((uint256(1) << 192) / quote) / quote;
    }


    /// 说明：给定 token0 数量和价格区间，计算能得到的流动性.计算 amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    ///  sqrtRatioAX96：第一个 tick 边界对应的平方根价格
    ///  sqrtRatioBX96：第二个 tick 边界对应的平方根价格
    ///  amount0：投入的 token0 数量
    ///  liquidity：算出来的流动性数量
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    // 说明：给定 token1 数量和价格区间，计算能得到的流动性.计算 amount1 / (sqrt(upper) - sqrt(lower))。
    //  sqrtRatioAX96：第一个 tick 边界对应的平方根价格
    //  sqrtRatioBX96：第二个 tick 边界对应的平方根价格
    //  amount1：投入的 token1 数量
    //  liquidity：算出来的流动性数量
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return toUint128(FullMath.mulDiv(amount1, Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }


    /// 把 uint256 向下收窄成 uint128
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

// 修改管理员
    function changeAdmin(address newAdmin) public {
        require(msg.sender == admin, "Only admin can change admin");
        admin = newAdmin;
    }

    modifier onlyAdmin {
        require(msg.sender == admin, "Only admin can call this function");
        _;
        
    }

// 虚拟份额
    function _decimalsOffset() internal view override returns (uint8) {
        return 12;
    }


// 重写父类方法，单币入口不合适本金库
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        revert();
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        revert();
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        revert();
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        revert();
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        revert();
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        revert();
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        revert();
    }
    
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        revert();
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return 0;
    }
    
    function maxDeposit(address owner) public view override returns (uint256) {
        return 0;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        return 0;
    }
    
    
    
    

    
}



