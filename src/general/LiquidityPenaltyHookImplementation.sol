// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LiquidityPenaltyHook} from "./LiquidityPenaltyHook.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

contract LiquidityPenaltyHookImplementation is LiquidityPenaltyHook {
    constructor(address _superHook, IPoolManager _poolManager, uint48 _blockNumberOffset)
        BaseSubHook(_superHook, _poolManager)
        LiquidityPenaltyHook(_blockNumberOffset)
    {}
}
