// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickBitmap} from "@uniswap/v4-core/src/libraries/TickBitmap.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {
    IERC20Minimal
} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {
    Currency,
    CurrencyLibrary
} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LiquidityMath} from "@uniswap/v4-core/src/libraries/LiquidityMath.sol";

import {TransferHelper} from "./libraries/TransferHelper.sol";
import {TwammMath} from "./libraries/TwammMath.sol";
import {OrderPool} from "./libraries/OrderPool.sol";
import {PoolGetters} from "./libraries/PoolGetters.sol";

import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {BaseHook} from "@superhook/external/BaseHook.sol";
import {BaseSuperHookUnlocker} from "@superhook/base/BaseSuperHookUnlocker.sol";

interface ITWAMM {
    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param owner The owner of the order
    /// @param currentAccount The invalid account attempting to interact with the order
    error MustBeOwner(address owner, address currentAccount);

    /// @notice Thrown when trying to cancel an already completed order
    /// @param orderKey The orderKey
    error CannotModifyCompletedOrder(OrderKey orderKey);

    /// @notice Thrown when trying to submit an order with an expiration that isn't on the interval.
    /// @param expiration The expiration timestamp of the order
    error ExpirationNotOnInterval(uint256 expiration);

    /// @notice Thrown when trying to submit an order with an expiration time in the past.
    /// @param expiration The expiration timestamp of the order
    error ExpirationLessThanBlocktime(uint256 expiration);

    /// @notice Thrown when trying to submit an order without initializing TWAMM state first
    error NotInitialized();

    /// @notice Thrown when trying to submit an order that's already ongoing.
    /// @param orderKey The already existing orderKey
    error OrderAlreadyExists(OrderKey orderKey);

    /// @notice Thrown when trying to interact with an order that does not exist.
    /// @param orderKey The already existing orderKey
    error OrderDoesNotExist(OrderKey orderKey);

    /// @notice Thrown when trying to subtract more value from a long term order than exists
    /// @param orderKey The orderKey
    /// @param unsoldAmount The amount still unsold
    /// @param amountDelta The amount delta for the order
    error InvalidAmountDelta(
        OrderKey orderKey,
        uint256 unsoldAmount,
        int256 amountDelta
    );

    /// @notice Thrown when submitting an order with a sellRate of 0
    error SellRateCannotBeZero();

    /// @notice Information associated with a long term order
    /// @member sellRate Amount of tokens sold per interval
    /// @member earningsFactorLast The accrued earnings factor from which to start claiming owed earnings for this order
    struct Order {
        uint256 sellRate;
        uint256 earningsFactorLast;
    }

    /// @notice Information that identifies an order
    /// @member owner Owner of the order
    /// @member expiration Timestamp when the order expires
    /// @member zeroForOne Bool whether the order is zeroForOne
    struct OrderKey {
        address owner;
        uint160 expiration;
        bool zeroForOne;
    }

    /// @notice Emitted when a new long term order is submitted
    /// @param poolId The id of the corresponding pool
    /// @param owner The owner of the new order
    /// @param expiration The expiration timestamp of the order
    /// @param zeroForOne Whether the order is selling token 0 for token 1
    /// @param sellRate The sell rate of tokens per second being sold in the order
    /// @param earningsFactorLast The current earningsFactor of the order pool
    event SubmitOrder(
        PoolId indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    /// @notice Emitted when a long term order is updated
    /// @param poolId The id of the corresponding pool
    /// @param owner The owner of the existing order
    /// @param expiration The expiration timestamp of the order
    /// @param zeroForOne Whether the order is selling token 0 for token 1
    /// @param sellRate The updated sellRate of tokens per second being sold in the order
    /// @param earningsFactorLast The current earningsFactor of the order pool
    ///   (since updated orders will claim existing earnings)
    event UpdateOrder(
        PoolId indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    /// @notice Time interval on which orders are allowed to expire. Conserves processing needed on execute.
    function expirationInterval() external view returns (uint256);

    /// @notice Submits a new long term order into the TWAMM. Also executes TWAMM orders if not up to date.
    /// @param key The PoolKey for which to identify the amm pool of the order
    /// @param orderKey The OrderKey for the new order
    /// @param amountIn The amount of sell token to add to the order. Some precision on amountIn may be lost up to the
    /// magnitude of (orderKey.expiration - block.timestamp)
    /// @return orderId The bytes32 ID of the order
    function submitOrder(
        PoolKey calldata key,
        OrderKey calldata orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId);

    /// @notice Update an existing long term order with current earnings, optionally modify the amount selling.
    /// @param key The PoolKey for which to identify the amm pool of the order
    /// @param orderKey The OrderKey for which to identify the order
    /// @param amountDelta The delta for the order sell amount. Negative to remove from order, positive to add, or
    ///    -1 to remove full amount from order.
    function updateOrder(
        PoolKey calldata key,
        OrderKey calldata orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed);

    /// @notice Claim tokens owed from TWAMM contract
    /// @param token The token to claim
    /// @param to The receipient of the claim
    /// @param amountRequested The amount of tokens requested to claim. Set to 0 to claim all.
    /// @return amountTransferred The total token amount to be collected
    function claimTokens(
        Currency token,
        address to,
        uint256 amountRequested
    ) external returns (uint256 amountTransferred);

    /// @notice Executes TWAMM orders on the pool, swapping on the pool itself to make up the difference between the
    /// two TWAMM pools swapping against each other
    /// @param key The pool key associated with the TWAMM
    function executeTWAMMOrders(PoolKey memory key) external;

    function tokensOwed(
        Currency token,
        address owner
    ) external returns (uint256);
}

contract TWAMM is BaseSuperHookUnlocker, ITWAMM {
    using TransferHelper for IERC20Minimal;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using OrderPool for OrderPool.State;
    using PoolIdLibrary for PoolKey;
    using TickMath for int24;
    using TickMath for uint160;
    using SafeCast for uint256;
    using PoolGetters for IPoolManager;
    using TickBitmap for mapping(int16 => uint256);
    using StateLibrary for IPoolManager;

    bytes internal constant ZERO_BYTES = bytes("");

    int256 internal constant MIN_DELTA = -1;
    bool internal constant ZERO_FOR_ONE = true;
    bool internal constant ONE_FOR_ZERO = false;

    /// @notice Contains full state related to the TWAMM
    /// @member lastVirtualOrderTimestamp Last timestamp in which virtual orders were executed
    /// @member orderPool0For1 Order pool trading token0 for token1 of pool
    /// @member orderPool1For0 Order pool trading token1 for token0 of pool
    /// @member orders Mapping of orderId to individual orders on pool
    struct State {
        uint256 lastVirtualOrderTimestamp;
        OrderPool.State orderPool0For1;
        OrderPool.State orderPool1For0;
        mapping(bytes32 => Order) orders;
    }

    /// @inheritdoc ITWAMM
    uint256 public immutable expirationInterval;
    // twammStates[poolId] => Twamm.State
    mapping(PoolId => State) internal twammStates;
    // tokensOwed[token][owner] => amountOwed
    mapping(Currency => mapping(address => uint256)) public tokensOwed;

    constructor(
        address _superHook,
        IPoolManager _manager,
        uint256 _expirationInterval
    ) BaseSuperHookUnlocker(_superHook, _manager) {
        expirationInterval = _expirationInterval;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal virtual override returns (bytes4) {
        // one-time initialization enforced in PoolManager
        initialize(_getTWAMM(key));
        return BaseHook.beforeInitialize.selector;
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        executeTWAMMOrders(key);
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        executeTWAMMOrders(key);
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function lastVirtualOrderTimestamp(
        PoolId key
    ) external view returns (uint256) {
        return twammStates[key].lastVirtualOrderTimestamp;
    }

    function getOrder(
        PoolKey calldata poolKey,
        OrderKey calldata orderKey
    ) external view returns (Order memory) {
        return
            _getOrder(
                twammStates[PoolId.wrap(keccak256(abi.encode(poolKey)))],
                orderKey
            );
    }

    function getOrderPool(
        PoolKey calldata key,
        bool zeroForOne
    )
        external
        view
        returns (uint256 sellRateCurrent, uint256 earningsFactorCurrent)
    {
        State storage twamm = _getTWAMM(key);
        return
            zeroForOne
                ? (
                    twamm.orderPool0For1.sellRateCurrent,
                    twamm.orderPool0For1.earningsFactorCurrent
                )
                : (
                    twamm.orderPool1For0.sellRateCurrent,
                    twamm.orderPool1For0.earningsFactorCurrent
                );
    }

    /// @notice Initialize TWAMM state
    function initialize(State storage self) internal {
        self.lastVirtualOrderTimestamp = block.timestamp;
    }

    /// @inheritdoc ITWAMM
    function executeTWAMMOrders(PoolKey memory key) public {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        State storage twamm = twammStates[poolId];
        if (twamm.lastVirtualOrderTimestamp == 0) revert NotInitialized();

        (bool zeroForOne, uint160 sqrtPriceLimitX96) = _executeTWAMMOrders(
            twamm,
            poolManager,
            key,
            PoolParamsOnExecute(sqrtPriceX96, poolManager.getLiquidity(poolId))
        );

        if (sqrtPriceLimitX96 != 0 && sqrtPriceLimitX96 != sqrtPriceX96) {
            // we trade to the sqrtPriceLimitX96, but v3 math inherently has small imprecision, must set swapAmountLimit
            // to balance in case the trade needs more wei than is left in the contract
            int256 swapAmountLimit = -int256(
                zeroForOne
                    ? key.currency0.balanceOfSelf()
                    : key.currency1.balanceOfSelf()
            );
            _unlock(
                poolId,
                abi.encode(
                    key,
                    SwapParams(zeroForOne, swapAmountLimit, sqrtPriceLimitX96)
                )
            );
        }
    }

    /// @inheritdoc ITWAMM
    function submitOrder(
        PoolKey calldata key,
        OrderKey memory orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId) {
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(key)));
        State storage twamm = twammStates[poolId];
        executeTWAMMOrders(key);

        uint256 sellRate;
        unchecked {
            // checks done in TWAMM library
            uint256 duration = orderKey.expiration - block.timestamp;
            sellRate = amountIn / duration;
            orderId = _submitOrder(twamm, orderKey, sellRate);
            IERC20Minimal(
                orderKey.zeroForOne
                    ? Currency.unwrap(key.currency0)
                    : Currency.unwrap(key.currency1)
            ).safeTransferFrom(msg.sender, address(this), sellRate * duration);
        }

        emit SubmitOrder(
            poolId,
            orderKey.owner,
            orderKey.expiration,
            orderKey.zeroForOne,
            sellRate,
            _getOrder(twamm, orderKey).earningsFactorLast
        );
    }

    /// @notice Submits a new long term order into the TWAMM
    /// @dev executeTWAMMOrders must be executed up to current timestamp before calling submitOrder
    /// @param orderKey The OrderKey for the new order
    function _submitOrder(
        State storage self,
        OrderKey memory orderKey,
        uint256 sellRate
    ) internal returns (bytes32 orderId) {
        if (orderKey.owner != msg.sender)
            revert MustBeOwner(orderKey.owner, msg.sender);
        if (self.lastVirtualOrderTimestamp == 0) revert NotInitialized();
        if (orderKey.expiration <= block.timestamp)
            revert ExpirationLessThanBlocktime(orderKey.expiration);
        if (sellRate == 0) revert SellRateCannotBeZero();
        if (orderKey.expiration % expirationInterval != 0)
            revert ExpirationNotOnInterval(orderKey.expiration);

        orderId = _orderId(orderKey);
        if (self.orders[orderId].sellRate != 0)
            revert OrderAlreadyExists(orderKey);

        OrderPool.State storage orderPool = orderKey.zeroForOne
            ? self.orderPool0For1
            : self.orderPool1For0;

        unchecked {
            orderPool.sellRateCurrent += sellRate;
            orderPool.sellRateEndingAtInterval[orderKey.expiration] += sellRate;
        }

        self.orders[orderId] = Order({
            sellRate: sellRate,
            earningsFactorLast: orderPool.earningsFactorCurrent
        });
    }

    /// @inheritdoc ITWAMM
    function updateOrder(
        PoolKey memory key,
        OrderKey memory orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed) {
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(key)));
        State storage twamm = twammStates[poolId];

        executeTWAMMOrders(key);

        // This call reverts if the caller is not the owner of the order
        (
            uint256 buyTokensOwed,
            uint256 sellTokensOwed,
            uint256 newSellrate,
            uint256 newEarningsFactorLast
        ) = _updateOrder(twamm, orderKey, amountDelta);

        if (orderKey.zeroForOne) {
            tokens0Owed += sellTokensOwed;
            tokens1Owed += buyTokensOwed;
        } else {
            tokens0Owed += buyTokensOwed;
            tokens1Owed += sellTokensOwed;
        }

        tokensOwed[key.currency0][orderKey.owner] += tokens0Owed;
        tokensOwed[key.currency1][orderKey.owner] += tokens1Owed;

        if (amountDelta > 0) {
            IERC20Minimal(
                orderKey.zeroForOne
                    ? Currency.unwrap(key.currency0)
                    : Currency.unwrap(key.currency1)
            ).safeTransferFrom(msg.sender, address(this), uint256(amountDelta));
        }

        emit UpdateOrder(
            poolId,
            orderKey.owner,
            orderKey.expiration,
            orderKey.zeroForOne,
            newSellrate,
            newEarningsFactorLast
        );
    }

    function _updateOrder(
        State storage self,
        OrderKey memory orderKey,
        int256 amountDelta
    )
        internal
        returns (
            uint256 buyTokensOwed,
            uint256 sellTokensOwed,
            uint256 newSellRate,
            uint256 earningsFactorLast
        )
    {
        Order storage order = _getOrder(self, orderKey);
        OrderPool.State storage orderPool = orderKey.zeroForOne
            ? self.orderPool0For1
            : self.orderPool1For0;

        if (orderKey.owner != msg.sender)
            revert MustBeOwner(orderKey.owner, msg.sender);
        if (order.sellRate == 0) revert OrderDoesNotExist(orderKey);
        if (amountDelta != 0 && orderKey.expiration <= block.timestamp)
            revert CannotModifyCompletedOrder(orderKey);

        unchecked {
            earningsFactorLast = orderKey.expiration <= block.timestamp
                ? orderPool.earningsFactorAtInterval[orderKey.expiration]
                : orderPool.earningsFactorCurrent;
            buyTokensOwed =
                ((earningsFactorLast - order.earningsFactorLast) *
                    order.sellRate) >>
                FixedPoint96.RESOLUTION;

            if (orderKey.expiration <= block.timestamp) {
                delete self.orders[_orderId(orderKey)];
            } else {
                order.earningsFactorLast = earningsFactorLast;
            }

            if (amountDelta != 0) {
                uint256 duration = orderKey.expiration - block.timestamp;
                uint256 unsoldAmount = order.sellRate * duration;
                if (amountDelta == MIN_DELTA)
                    amountDelta = -(unsoldAmount.toInt256());
                int256 newSellAmount = unsoldAmount.toInt256() + amountDelta;
                if (newSellAmount < 0)
                    revert InvalidAmountDelta(
                        orderKey,
                        unsoldAmount,
                        amountDelta
                    );

                newSellRate = uint256(newSellAmount) / duration;

                if (amountDelta < 0) {
                    uint256 sellRateDelta = order.sellRate - newSellRate;
                    orderPool.sellRateCurrent -= sellRateDelta;
                    orderPool.sellRateEndingAtInterval[
                        orderKey.expiration
                    ] -= sellRateDelta;
                    sellTokensOwed = uint256(-amountDelta);
                } else {
                    uint256 sellRateDelta = newSellRate - order.sellRate;
                    orderPool.sellRateCurrent += sellRateDelta;
                    orderPool.sellRateEndingAtInterval[
                        orderKey.expiration
                    ] += sellRateDelta;
                }
                if (newSellRate == 0) {
                    delete self.orders[_orderId(orderKey)];
                } else {
                    order.sellRate = newSellRate;
                }
            }
        }
    }

    /// @inheritdoc ITWAMM
    function claimTokens(
        Currency token,
        address to,
        uint256 amountRequested
    ) external returns (uint256 amountTransferred) {
        uint256 currentBalance = token.balanceOfSelf();
        amountTransferred = tokensOwed[token][msg.sender];
        if (amountRequested != 0 && amountRequested < amountTransferred)
            amountTransferred = amountRequested;
        if (currentBalance < amountTransferred)
            amountTransferred = currentBalance; // to catch precision errors
        tokensOwed[token][msg.sender] -= amountTransferred;
        IERC20Minimal(Currency.unwrap(token)).safeTransfer(
            to,
            amountTransferred
        );
    }

    function _subHookUnlockCallback(
        PoolId,
        bytes memory rawData
    ) internal override returns (bytes memory) {
        (PoolKey memory key, SwapParams memory swapParams) = abi.decode(
            rawData,
            (PoolKey, SwapParams)
        );

        BalanceDelta delta = poolManager.swap(key, swapParams, ZERO_BYTES);

        if (swapParams.zeroForOne) {
            if (delta.amount0() < 0) {
                key.currency0.settle(
                    poolManager,
                    address(this),
                    uint256(uint128(-delta.amount0())),
                    false
                );
            }
            if (delta.amount1() > 0) {
                key.currency1.take(
                    poolManager,
                    address(this),
                    uint256(uint128(delta.amount1())),
                    false
                );
            }
        } else {
            if (delta.amount1() < 0) {
                key.currency1.settle(
                    poolManager,
                    address(this),
                    uint256(uint128(-delta.amount1())),
                    false
                );
            }
            if (delta.amount0() > 0) {
                key.currency0.take(
                    poolManager,
                    address(this),
                    uint256(uint128(delta.amount0())),
                    false
                );
            }
        }
        return bytes("");
    }

    function _getTWAMM(
        PoolKey memory key
    ) private view returns (State storage) {
        return twammStates[PoolId.wrap(keccak256(abi.encode(key)))];
    }

    struct PoolParamsOnExecute {
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    /// @notice Executes all existing long term orders in the TWAMM
    /// @param pool The relevant state of the pool
    function _executeTWAMMOrders(
        State storage self,
        IPoolManager manager,
        PoolKey memory key,
        PoolParamsOnExecute memory pool
    ) internal returns (bool zeroForOne, uint160 newSqrtPriceX96) {
        if (!_hasOutstandingOrders(self)) {
            self.lastVirtualOrderTimestamp = block.timestamp;
            return (false, 0);
        }

        uint160 initialSqrtPriceX96 = pool.sqrtPriceX96;
        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = prevTimestamp +
            (expirationInterval - (prevTimestamp % expirationInterval));

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        unchecked {
            while (nextExpirationTimestamp <= block.timestamp) {
                if (
                    orderPool0For1.sellRateEndingAtInterval[
                        nextExpirationTimestamp
                    ] >
                    0 ||
                    orderPool1For0.sellRateEndingAtInterval[
                        nextExpirationTimestamp
                    ] >
                    0
                ) {
                    if (
                        orderPool0For1.sellRateCurrent != 0 &&
                        orderPool1For0.sellRateCurrent != 0
                    ) {
                        pool = _advanceToNewTimestamp(
                            self,
                            key,
                            AdvanceParams(
                                expirationInterval,
                                nextExpirationTimestamp,
                                nextExpirationTimestamp - prevTimestamp,
                                pool
                            )
                        );
                    } else {
                        pool = _advanceTimestampForSinglePoolSell(
                            self,
                            key,
                            AdvanceSingleParams(
                                expirationInterval,
                                nextExpirationTimestamp,
                                nextExpirationTimestamp - prevTimestamp,
                                pool,
                                orderPool0For1.sellRateCurrent != 0
                            )
                        );
                    }
                    prevTimestamp = nextExpirationTimestamp;
                }
                nextExpirationTimestamp += expirationInterval;

                if (!_hasOutstandingOrders(self)) break;
            }

            if (
                prevTimestamp < block.timestamp && _hasOutstandingOrders(self)
            ) {
                if (
                    orderPool0For1.sellRateCurrent != 0 &&
                    orderPool1For0.sellRateCurrent != 0
                ) {
                    pool = _advanceToNewTimestamp(
                        self,
                        key,
                        AdvanceParams(
                            expirationInterval,
                            block.timestamp,
                            block.timestamp - prevTimestamp,
                            pool
                        )
                    );
                } else {
                    pool = _advanceTimestampForSinglePoolSell(
                        self,
                        key,
                        AdvanceSingleParams(
                            expirationInterval,
                            block.timestamp,
                            block.timestamp - prevTimestamp,
                            pool,
                            orderPool0For1.sellRateCurrent != 0
                        )
                    );
                }
            }
        }

        self.lastVirtualOrderTimestamp = block.timestamp;
        newSqrtPriceX96 = pool.sqrtPriceX96;
        zeroForOne = initialSqrtPriceX96 > newSqrtPriceX96;
    }

    struct AdvanceParams {
        uint256 expirationInterval;
        uint256 nextTimestamp;
        uint256 secondsElapsed;
        PoolParamsOnExecute pool;
    }

    function _advanceToNewTimestamp(
        State storage self,
        PoolKey memory poolKey,
        AdvanceParams memory params
    ) private returns (PoolParamsOnExecute memory) {
        uint160 finalSqrtPriceX96;
        uint256 secondsElapsedX96 = params.secondsElapsed * FixedPoint96.Q96;

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        while (true) {
            TwammMath.ExecutionUpdateParams memory executionParams = TwammMath
                .ExecutionUpdateParams(
                    secondsElapsedX96,
                    params.pool.sqrtPriceX96,
                    params.pool.liquidity,
                    orderPool0For1.sellRateCurrent,
                    orderPool1For0.sellRateCurrent
                );

            finalSqrtPriceX96 = TwammMath.getNewSqrtPriceX96(executionParams);

            (
                bool crossingInitializedTick,
                int24 tick
            ) = _isCrossingInitializedTick(
                    params.pool,
                    poolKey,
                    finalSqrtPriceX96
                );
            unchecked {
                if (crossingInitializedTick) {
                    uint256 secondsUntilCrossingX96;
                    (
                        params.pool,
                        secondsUntilCrossingX96
                    ) = _advanceTimeThroughTickCrossing(
                        self,
                        poolKey,
                        TickCrossingParams(
                            tick,
                            params.nextTimestamp,
                            secondsElapsedX96,
                            params.pool
                        )
                    );
                    secondsElapsedX96 =
                        secondsElapsedX96 -
                        secondsUntilCrossingX96;
                } else {
                    (
                        uint256 earningsFactorPool0,
                        uint256 earningsFactorPool1
                    ) = TwammMath.calculateEarningsUpdates(
                            executionParams,
                            finalSqrtPriceX96
                        );

                    if (params.nextTimestamp % params.expirationInterval == 0) {
                        orderPool0For1.advanceToInterval(
                            params.nextTimestamp,
                            earningsFactorPool0
                        );
                        orderPool1For0.advanceToInterval(
                            params.nextTimestamp,
                            earningsFactorPool1
                        );
                    } else {
                        orderPool0For1.advanceToCurrentTime(
                            earningsFactorPool0
                        );
                        orderPool1For0.advanceToCurrentTime(
                            earningsFactorPool1
                        );
                    }
                    params.pool.sqrtPriceX96 = finalSqrtPriceX96;
                    break;
                }
            }
        }

        return params.pool;
    }

    struct AdvanceSingleParams {
        uint256 expirationInterval;
        uint256 nextTimestamp;
        uint256 secondsElapsed;
        PoolParamsOnExecute pool;
        bool zeroForOne;
    }

    function _advanceTimestampForSinglePoolSell(
        State storage self,
        PoolKey memory poolKey,
        AdvanceSingleParams memory params
    ) private returns (PoolParamsOnExecute memory) {
        OrderPool.State storage orderPool = params.zeroForOne
            ? self.orderPool0For1
            : self.orderPool1For0;
        uint256 sellRateCurrent = orderPool.sellRateCurrent;
        uint256 amountSelling = sellRateCurrent * params.secondsElapsed;
        uint256 totalEarnings;

        while (true) {
            uint160 finalSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                params.pool.sqrtPriceX96,
                params.pool.liquidity,
                amountSelling,
                params.zeroForOne
            );

            (
                bool crossingInitializedTick,
                int24 tick
            ) = _isCrossingInitializedTick(
                    params.pool,
                    poolKey,
                    finalSqrtPriceX96
                );

            if (crossingInitializedTick) {
                (, int128 liquidityNetAtTick) = poolManager.getTickLiquidity(
                    poolKey.toId(),
                    tick
                );
                uint160 initializedSqrtPrice = TickMath.getSqrtPriceAtTick(
                    tick
                );

                uint256 swapDelta0 = SqrtPriceMath.getAmount0Delta(
                    params.pool.sqrtPriceX96,
                    initializedSqrtPrice,
                    params.pool.liquidity,
                    true
                );
                uint256 swapDelta1 = SqrtPriceMath.getAmount1Delta(
                    params.pool.sqrtPriceX96,
                    initializedSqrtPrice,
                    params.pool.liquidity,
                    true
                );

                if (params.zeroForOne) liquidityNetAtTick = -liquidityNetAtTick;
                params.pool.liquidity = LiquidityMath.addDelta(
                    params.pool.liquidity,
                    liquidityNetAtTick
                );
                params.pool.sqrtPriceX96 = initializedSqrtPrice;

                unchecked {
                    totalEarnings += params.zeroForOne
                        ? swapDelta1
                        : swapDelta0;
                    amountSelling -= params.zeroForOne
                        ? swapDelta0
                        : swapDelta1;
                }
            } else {
                if (params.zeroForOne) {
                    totalEarnings += SqrtPriceMath.getAmount1Delta(
                        params.pool.sqrtPriceX96,
                        finalSqrtPriceX96,
                        params.pool.liquidity,
                        true
                    );
                } else {
                    totalEarnings += SqrtPriceMath.getAmount0Delta(
                        params.pool.sqrtPriceX96,
                        finalSqrtPriceX96,
                        params.pool.liquidity,
                        true
                    );
                }

                uint256 accruedEarningsFactor = (totalEarnings *
                    FixedPoint96.Q96) / sellRateCurrent;

                if (params.nextTimestamp % params.expirationInterval == 0) {
                    orderPool.advanceToInterval(
                        params.nextTimestamp,
                        accruedEarningsFactor
                    );
                } else {
                    orderPool.advanceToCurrentTime(accruedEarningsFactor);
                }
                params.pool.sqrtPriceX96 = finalSqrtPriceX96;
                break;
            }
        }

        return params.pool;
    }

    struct TickCrossingParams {
        int24 initializedTick;
        uint256 nextTimestamp;
        uint256 secondsElapsedX96;
        PoolParamsOnExecute pool;
    }

    function _advanceTimeThroughTickCrossing(
        State storage self,
        PoolKey memory poolKey,
        TickCrossingParams memory params
    ) private returns (PoolParamsOnExecute memory, uint256) {
        uint160 initializedSqrtPrice = params
            .initializedTick
            .getSqrtPriceAtTick();

        uint256 secondsUntilCrossingX96 = TwammMath.calculateTimeBetweenTicks(
            params.pool.liquidity,
            params.pool.sqrtPriceX96,
            initializedSqrtPrice,
            self.orderPool0For1.sellRateCurrent,
            self.orderPool1For0.sellRateCurrent
        );

        (uint256 earningsFactorPool0, uint256 earningsFactorPool1) = TwammMath
            .calculateEarningsUpdates(
                TwammMath.ExecutionUpdateParams(
                    secondsUntilCrossingX96,
                    params.pool.sqrtPriceX96,
                    params.pool.liquidity,
                    self.orderPool0For1.sellRateCurrent,
                    self.orderPool1For0.sellRateCurrent
                ),
                initializedSqrtPrice
            );

        self.orderPool0For1.advanceToCurrentTime(earningsFactorPool0);
        self.orderPool1For0.advanceToCurrentTime(earningsFactorPool1);

        unchecked {
            // update pool
            (, int128 liquidityNet) = poolManager.getTickLiquidity(
                poolKey.toId(),
                params.initializedTick
            );
            if (initializedSqrtPrice < params.pool.sqrtPriceX96)
                liquidityNet = -liquidityNet;
            params.pool.liquidity = liquidityNet < 0
                ? params.pool.liquidity - uint128(-liquidityNet)
                : params.pool.liquidity + uint128(liquidityNet);

            params.pool.sqrtPriceX96 = initializedSqrtPrice;
        }
        return (params.pool, secondsUntilCrossingX96);
    }

    function _isCrossingInitializedTick(
        PoolParamsOnExecute memory pool,
        PoolKey memory poolKey,
        uint160 nextSqrtPriceX96
    ) internal view returns (bool crossingInitializedTick, int24 nextTickInit) {
        // use current price as a starting point for nextTickInit
        nextTickInit = pool.sqrtPriceX96.getTickAtSqrtPrice();
        int24 targetTick = nextSqrtPriceX96.getTickAtSqrtPrice();
        bool searchingLeft = nextSqrtPriceX96 < pool.sqrtPriceX96;
        bool nextTickInitFurtherThanTarget = false; // initialize as false

        // nextTickInit returns the furthest tick within one word if no tick within that word is initialized
        // so we must keep iterating if we haven't reached a tick further than our target tick
        while (!nextTickInitFurtherThanTarget) {
            unchecked {
                if (searchingLeft) nextTickInit -= 1;
            }
            (nextTickInit, crossingInitializedTick) = poolManager
                .getNextInitializedTickWithinOneWord(
                    poolKey.toId(),
                    nextTickInit,
                    poolKey.tickSpacing,
                    searchingLeft
                );
            nextTickInitFurtherThanTarget = searchingLeft
                ? nextTickInit <= targetTick
                : nextTickInit > targetTick;
            if (crossingInitializedTick == true) break;
        }
        if (nextTickInitFurtherThanTarget) crossingInitializedTick = false;
    }

    function _getOrder(
        State storage self,
        OrderKey memory key
    ) internal view returns (Order storage) {
        return self.orders[_orderId(key)];
    }

    function _orderId(OrderKey memory key) private pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    function _hasOutstandingOrders(
        State storage self
    ) internal view returns (bool) {
        return
            self.orderPool0For1.sellRateCurrent != 0 ||
            self.orderPool1For0.sellRateCurrent != 0;
    }
}
