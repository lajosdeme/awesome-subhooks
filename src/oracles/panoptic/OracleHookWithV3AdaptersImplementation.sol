// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {OracleHookWithV3Adapters} from "./OracleHookWithV3Adapters.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

contract OracleHookWithV3AdaptersImplementation is OracleHookWithV3Adapters {
    constructor(address _superHook, IPoolManager _poolManager, int24 _maxAbsTickDelta)
        BaseSubHook(_superHook, _poolManager)
        OracleHookWithV3Adapters(_maxAbsTickDelta)
    {}
}
