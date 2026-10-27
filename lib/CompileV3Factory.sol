// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

// 只在 factory 配置里编译：FOUNDRY_PROFILE=factory forge build
// 放在 lib 目录里，用相对路径引用工厂。0.7.6 不允许 v3/ 里的文件再跳到 lib/。
import "./uniswap-v3-core/contracts/UniswapV3Factory.sol";

contract CompileV3Factory {}
