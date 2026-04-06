// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External imports
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// Internal imports
import {LimitOrderHook} from "../../general/LimitOrderHook.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

contract LimitOrderHookMock is LimitOrderHook {
    constructor(address _superHook, IPoolManager _poolManager) LimitOrderHook(_superHook, _poolManager) {}

    // exclude from coverage report
    function test() public {}
}
