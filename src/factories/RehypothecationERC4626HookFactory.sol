// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReHypothecationERC4626Hook} from "../general/ReHypothecationERC4626Hook.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

interface IRehypothecationERC4626HookFactory {
    function deployRehypothecationERC4626Hook(uint256 salt) external returns (address hook);
    function mineRehypothecationERC4626HookAddress() external view returns (address, uint256);
}

contract RehypothecationERC4626HookFactory {
    error ZeroAddress();

    event RehypothecationERC4626HookDeployed(address indexed hook);

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    constructor(address _superHook, IPoolManager _poolManager) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;
    }

    function deployRehypothecationERC4626Hook(uint256 salt) external returns (address hook) {
        ReHypothecationERC4626Hook hookContract = new ReHypothecationERC4626Hook{salt: bytes32(salt)}(
            superHook,
            poolManager,
            msg.sender
        );
        hook = address(hookContract);

        emit RehypothecationERC4626HookDeployed(hook);
    }

    function mineRehypothecationERC4626HookAddress()
        external
        view
        returns (address, uint256)
    {
        bytes memory initCode = abi.encodePacked(
            type(ReHypothecationERC4626Hook).creationCode,
            abi.encode(superHook, poolManager, msg.sender)
        );

        uint160 mask = HookMiner.permissionsToMask(
            true,
            false,
            false,
            false,
            false,
            false,
            true,
            true,
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