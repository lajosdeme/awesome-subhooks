// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {WhitelistHook} from "../awesome-hooks/WhitelistHook.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

interface IWhitelistHookFactory {
    function deployWhitelistHook(uint256 salt) external returns (address hook);
    function mineWhitelistHookAddress() external view returns (address, uint256);
}

contract WhitelistHookFactory {
    error ZeroAddress();

    event WhitelistHookDeployed(address indexed hook);

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    constructor(address _superHook, IPoolManager _poolManager) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;
    }

    function deployWhitelistHook(uint256 salt) external returns (address hook) {
        WhitelistHook hookContract = new WhitelistHook{salt: bytes32(salt)}(
            superHook,
            poolManager,
            msg.sender
        );
        hook = address(hookContract);

        emit WhitelistHookDeployed(hook);
    }

    function mineWhitelistHookAddress()
        external
        view
        returns (address, uint256)
    {
        bytes memory initCode = abi.encodePacked(
            type(WhitelistHook).creationCode,
            abi.encode(superHook, poolManager, msg.sender)
        );

        uint160 mask = HookMiner.permissionsToMask(
            false,
            false,
            true,
            false,
            true,
            false,
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            false
        );

        uint256 salt = HookMiner.findSaltForMask(address(this), initCode, mask);

        address predicted = HookMiner.computeCreate2Address(
            salt,
            keccak256(initCode),
            address(this)
        );

        return (predicted, salt);
    }
}