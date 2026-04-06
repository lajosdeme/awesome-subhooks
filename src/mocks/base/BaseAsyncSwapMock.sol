// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External imports
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// Internal imports
import {BaseAsyncSwap} from "../../base/BaseAsyncSwap.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

contract BaseAsyncSwapMock is BaseAsyncSwap {
    constructor(address _superHook, IPoolManager _poolManager) BaseSubHook(_superHook, _poolManager) {}

    // Exclude from coverage report
    function test() public {}
}
