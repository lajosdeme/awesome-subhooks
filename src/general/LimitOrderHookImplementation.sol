// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LimitOrderHook} from "./LimitOrderHook.sol";

contract LimitOrderHookImplementation is LimitOrderHook {
    constructor(address _superHook, IPoolManager _poolManager)
        LimitOrderHook(_superHook, _poolManager)
    {}
}