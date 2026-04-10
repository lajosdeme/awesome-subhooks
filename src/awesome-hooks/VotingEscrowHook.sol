// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";
import {
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";


contract VotingEscrow is BaseSubHook, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;

    event Deposit(address indexed provider, uint256 value, uint256 locktime, LockAction indexed action, uint256 ts);
    event Withdraw(address indexed provider, uint256 value, LockAction indexed action, uint256 ts);

    PoolId public poolId;

    ERC20 public token;
    bool initialized;
    uint256 public constant WEEK = 7 days;
    uint256 public constant MAXTIME = 365 days;
    uint256 public constant MULTIPLIER = 10 ** 18;

    uint256 public globalEpoch;
    Point[1000000000000000000] public pointHistory;
    mapping(address => Point[1000000000]) public userPointHistory;
    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges;
    mapping(address => LockedBalance) public locked;
    mapping(address => LockTicks) public lockTicks;

    string public name;
    string public symbol;
    uint256 public decimals = 18;

    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    struct LockedBalance {
        uint128 amount;
        uint128 end;
    }

    struct LockTicks {
        int24 lowerTick;
        int24 upperTick;
    }

    enum LockAction {
        CREATE,
        INCREASE_TIME
    }

    constructor(
        address _superHook,
        IPoolManager _poolManager,
        address _token,
        string memory _name,
        string memory _symbol
    ) BaseSubHook(_superHook, _poolManager) {
        token = ERC20(_token);
        pointHistory[0] = Point({bias: int128(0), slope: int128(0), ts: block.timestamp, blk: block.number});

        decimals = ERC20(_token).decimals();
        require(decimals <= 18, "Exceeds max decimals");

        name = _name;
        symbol = _symbol;
    }

    function getHookPermissions()
        public
        pure
        virtual
        override
        returns (Hooks.Permissions memory permissions)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24
    ) internal override returns (bytes4) {
        poolId = key.toId();
        return this.afterInitialize.selector;
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata modifyPositionParams,
        bytes calldata
    ) internal view override returns (bytes4) {
        LockTicks memory lockTicks_ = lockTicks[sender];
        if (
            lockTicks_.lowerTick != modifyPositionParams.tickLower
                || lockTicks_.upperTick != modifyPositionParams.tickUpper
        ) {
            return this.beforeAddLiquidity.selector;
        }

        LockedBalance memory locked_ = locked[sender];
        require(
            modifyPositionParams.liquidityDelta > 0 || locked_.end <= block.timestamp, "Can't withdraw before lock end"
        );
        return this.beforeAddLiquidity.selector;
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata modifyPositionParams,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        LockTicks memory lockTicks_ = lockTicks[sender];
        if (
            lockTicks_.lowerTick != modifyPositionParams.tickLower
                || lockTicks_.upperTick != modifyPositionParams.tickUpper
        ) {
            return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
        }

        bytes32 positionId = keccak256(abi.encode(poolId, sender, modifyPositionParams.tickLower, modifyPositionParams.tickUpper));
        (uint128 liquidity,,) = StateLibrary.getPositionInfo(poolManager, poolId, positionId);
        
        LockedBalance storage lockedRef = locked[sender];
        if (lockedRef.end > block.timestamp) {
            assert(lockedRef.amount < liquidity);
        }
        
        lockedRef.amount = liquidity;

        _checkpoint(sender, LockedBalance(lockedRef.amount, lockedRef.end), LockedBalance(uint128(liquidity), lockedRef.end));

        return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata modifyPositionParams,
        bytes calldata
    ) internal view override returns (bytes4) {
        LockTicks memory lockTicks_ = lockTicks[sender];
        if (
            lockTicks_.lowerTick != modifyPositionParams.tickLower
                || lockTicks_.upperTick != modifyPositionParams.tickUpper
        ) {
            return this.beforeRemoveLiquidity.selector;
        }

        LockedBalance memory locked_ = locked[sender];
        require(
            modifyPositionParams.liquidityDelta > 0 || locked_.end <= block.timestamp, "Can't withdraw before lock end"
        );
        return this.beforeRemoveLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata modifyPositionParams,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        LockTicks memory lockTicks_ = lockTicks[sender];
        if (
            lockTicks_.lowerTick != modifyPositionParams.tickLower
                || lockTicks_.upperTick != modifyPositionParams.tickUpper
        ) {
            return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
        }

        bytes32 positionId = keccak256(abi.encode(poolId, sender, modifyPositionParams.tickLower, modifyPositionParams.tickUpper));
        (uint128 liquidity,,) = StateLibrary.getPositionInfo(poolManager, poolId, positionId);
        
        LockedBalance storage lockedRef = locked[sender];
        if (lockedRef.end > block.timestamp) {
            assert(lockedRef.amount < liquidity);
        }
        
        lockedRef.amount = liquidity;

        _checkpoint(sender, LockedBalance(lockedRef.amount, lockedRef.end), LockedBalance(uint128(liquidity), lockedRef.end));

        return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function lockEnd(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    function getLastUserPoint(address _addr) external view returns (int128 bias, int128 slope, uint256 ts) {
        uint256 uepoch = userPointEpoch[_addr];
        if (uepoch == 0) {
            return (0, 0, 0);
        }
        Point memory point = userPointHistory[_addr][uepoch];
        return (point.bias, point.slope, point.ts);
    }

    function _checkpoint(address _addr, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        Point memory userOldPoint;
        Point memory userNewPoint;
        int128 oldSlopeDelta = 0;
        int128 newSlopeDelta = 0;
        uint256 epoch = globalEpoch;

        if (_addr != address(0)) {
            if (_oldLocked.end > block.timestamp) {
                userOldPoint.slope = int128(_oldLocked.amount) / int128(int256(MAXTIME));
                userOldPoint.bias = userOldPoint.slope * int128(int256(_oldLocked.end - block.timestamp));
            }
            if (_newLocked.end > block.timestamp) {
                userNewPoint.slope = int128(_newLocked.amount) / int128(int256(MAXTIME));
                userNewPoint.bias = userNewPoint.slope * int128(int256(_newLocked.end - block.timestamp));
            }

            uint256 uEpoch = userPointEpoch[_addr];
            if (uEpoch == 0) {
                userPointHistory[_addr][uEpoch + 1] = userOldPoint;
            }

            userPointEpoch[_addr] = uEpoch + 1;
            userNewPoint.ts = block.timestamp;
            userNewPoint.blk = block.number;
            userPointHistory[_addr][uEpoch + 1] = userNewPoint;

            oldSlopeDelta = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    newSlopeDelta = oldSlopeDelta;
                } else {
                    newSlopeDelta = slopeChanges[_newLocked.end];
                }
            }
        }

        Point memory lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});
        if (epoch > 0) {
            lastPoint = pointHistory[epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;

        Point memory initialLastPoint = Point({bias: 0, slope: 0, ts: lastPoint.ts, blk: lastPoint.blk});
        uint256 blockSlope = 0;
        if (block.timestamp > lastPoint.ts) {
            blockSlope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
        }

        uint256 iterativeTime = _floorToWeek(lastCheckpoint);
        for (uint256 i = 0; i < 255; i++) {
            iterativeTime = iterativeTime + WEEK;
            int128 dSlope = 0;
            if (iterativeTime > block.timestamp) {
                iterativeTime = block.timestamp;
            } else {
                dSlope = slopeChanges[iterativeTime];
            }
            int128 biasDelta = lastPoint.slope * int128(int256((iterativeTime - lastCheckpoint)));
            lastPoint.bias = lastPoint.bias - biasDelta;
            lastPoint.slope = lastPoint.slope + dSlope;
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            lastCheckpoint = iterativeTime;
            lastPoint.ts = iterativeTime;
            lastPoint.blk = initialLastPoint.blk + (blockSlope * (iterativeTime - initialLastPoint.ts)) / MULTIPLIER;

            epoch = epoch + 1;
            if (iterativeTime == block.timestamp) {
                lastPoint.blk = block.number;
                break;
            } else {
                pointHistory[epoch] = lastPoint;
            }
        }

        globalEpoch = epoch;

        if (_addr != address(0)) {
            lastPoint.slope = lastPoint.slope + userNewPoint.slope - userOldPoint.slope;
            lastPoint.bias = lastPoint.bias + userNewPoint.bias - userOldPoint.bias;
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }

        pointHistory[epoch] = lastPoint;

        if (_addr != address(0)) {
            if (_oldLocked.end > block.timestamp) {
                oldSlopeDelta = oldSlopeDelta + userOldPoint.slope;
                if (_newLocked.end == _oldLocked.end) {
                    oldSlopeDelta = oldSlopeDelta - userNewPoint.slope;
                }
                slopeChanges[_oldLocked.end] = oldSlopeDelta;
            }
            if (_newLocked.end > block.timestamp) {
                if (_newLocked.end > _oldLocked.end) {
                    newSlopeDelta = newSlopeDelta - userNewPoint.slope;
                    slopeChanges[_newLocked.end] = newSlopeDelta;
                }
            }
        }
    }

    function checkpoint() external {
        LockedBalance memory empty;
        _checkpoint(address(0), empty, empty);
    }

    function createLock(uint256 _unlockTime, int24 _tickLower, int24 _tickUpper) external nonReentrant {
        uint256 unlock_time = _floorToWeek(_unlockTime);
        LockedBalance memory locked_ = locked[msg.sender];
        bytes32 positionId = keccak256(abi.encode(poolId, msg.sender, _tickLower, _tickUpper));
        (uint128 liquidity,,) = StateLibrary.getPositionInfo(poolManager, poolId, positionId);
        uint256 value = uint256(liquidity);

        require(value > 0, "No liquidity position");
        require(locked_.amount == 0, "Lock exists");
        require(unlock_time >= locked_.end, "Only increase lock end");
        require(unlock_time > block.timestamp, "Only future lock end");
        require(unlock_time <= block.timestamp + MAXTIME, "Exceeds maxtime");
        locked_.amount = uint128(value);
        locked_.end = uint128(unlock_time);
        locked[msg.sender] = locked_;
        lockTicks[msg.sender] = LockTicks({lowerTick: _tickLower, upperTick: _tickUpper});
        _checkpoint(msg.sender, LockedBalance(0, 0), locked_);
        emit Deposit(msg.sender, value, unlock_time, LockAction.CREATE, block.timestamp);
    }

    function increaseUnlockTime(uint256 _unlockTime) external nonReentrant {
        LockedBalance memory locked_ = locked[msg.sender];
        uint256 unlock_time = _floorToWeek(_unlockTime);
        require(locked_.amount > 0, "No lock");
        require(unlock_time > locked_.end, "Only increase lock end");
        require(unlock_time <= block.timestamp + MAXTIME, "Exceeds maxtime");
        uint256 oldUnlockTime = locked_.end;
        locked_.end = uint128(unlock_time);
        locked[msg.sender] = locked_;
        require(oldUnlockTime > block.timestamp, "Lock expired");
        LockedBalance memory oldLocked = _copyLock(locked_);
        oldLocked.end = uint128(oldUnlockTime);
        _checkpoint(msg.sender, oldLocked, locked_);
        emit Deposit(msg.sender, 0, unlock_time, LockAction.INCREASE_TIME, block.timestamp);
    }

    function _copyLock(LockedBalance memory _locked) internal pure returns (LockedBalance memory) {
        return LockedBalance({amount: _locked.amount, end: _locked.end});
    }

    function _floorToWeek(uint256 _t) internal pure returns (uint256) {
        return (_t / WEEK) * WEEK;
    }
}
