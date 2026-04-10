// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

interface ITWAMM {
    error MustBeOwner(address owner, address currentAccount);
    error CannotModifyCompletedOrder(OrderKey orderKey);
    error ExpirationNotOnInterval(uint256 expiration);
    error ExpirationLessThanBlocktime(uint256 expiration);
    error NotInitialized();
    error OrderAlreadyExists(OrderKey orderKey);
    error OrderDoesNotExist(OrderKey orderKey);
    error InvalidAmountDelta(OrderKey orderKey, uint256 unsoldAmount, int256 amountDelta);
    error SellRateCannotBeZero();

    struct Order {
        uint256 sellRate;
        uint256 earningsFactorLast;
    }

    struct OrderKey {
        address owner;
        uint160 expiration;
        bool zeroForOne;
    }

    event SubmitOrder(
        PoolId indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    event UpdateOrder(
        PoolId indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    function expirationInterval() external view returns (uint256);

    function submitOrder(
        PoolKey calldata key,
        OrderKey calldata orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId);

    function updateOrder(
        PoolKey calldata key,
        OrderKey calldata orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed);

    function claimTokens(
        Currency token,
        address to,
        uint256 amountRequested
    ) external returns (uint256 amountTransferred);

    function executeTWAMMOrders(PoolKey memory key) external;

    function tokensOwed(Currency token, address owner) external returns (uint256);
}