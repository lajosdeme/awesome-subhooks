// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MultiSigSwapHook} from "../awesome-hooks/MultiSigSwapHook.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

interface IMultiSigSwapHookFactory {
    function deployMultiSigSwapHook(
        uint256 salt,
        address[] memory signers,
        uint256 requiredSignatures
    ) external returns (address hook);
    function mineMultiSigSwapHookAddress(
        address[] memory signers,
        uint256 requiredSignatures
    ) external view returns (address, uint256);
}

contract MultiSigSwapHookFactory {
    error ZeroAddress();

    event MultiSigSwapHookDeployed(address indexed hook);

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    constructor(address _superHook, IPoolManager _poolManager) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;
    }

    function deployMultiSigSwapHook(
        uint256 salt,
        address[] memory signers,
        uint256 requiredSignatures
    ) external returns (address hook) {
        MultiSigSwapHook hookContract = new MultiSigSwapHook{salt: bytes32(salt)}(
            superHook,
            poolManager,
            signers,
            requiredSignatures
        );
        hook = address(hookContract);

        emit MultiSigSwapHookDeployed(hook);
    }

    function mineMultiSigSwapHookAddress(
        address[] memory signers,
        uint256 requiredSignatures
    ) external view returns (address, uint256) {
        bytes memory initCode = abi.encodePacked(
            type(MultiSigSwapHook).creationCode,
            abi.encode(superHook, poolManager, signers, requiredSignatures)
        );

        uint160 mask = HookMiner.permissionsToMask(
            false,
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