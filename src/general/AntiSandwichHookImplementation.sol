// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {AntiSandwichHook} from "./AntiSandwichHook.sol";
import {CurrencySettler} from "../utils/CurrencySettler.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

contract AntiSandwichHookImplementation is AntiSandwichHook {
    using CurrencySettler for Currency;

    constructor(address _superHook, IPoolManager _poolManager) BaseSubHook(_superHook, _poolManager) {}

    function _afterSwapHandler(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        uint256,
        uint256 feeAmount
    ) internal override {
        Currency unspecified = (params.amountSpecified < 0 == params.zeroForOne) ? (key.currency1) : (key.currency0);
        (uint256 amount0, uint256 amount1) = unspecified == key.currency0
            ? (uint256(uint128(feeAmount)), uint256(0))
            : (uint256(0), uint256(uint128(feeAmount)));

        poolManager.donate(key, amount0, amount1, "");
        unspecified.settle(poolManager, address(this), feeAmount, true);
    }
}
