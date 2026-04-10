// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {KYCSwaps} from "../awesome-hooks/KYCHook.sol";
import {SimpleKYCContract} from "../general/SimpleKYCContract.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

interface IKYCHookFactory {
    function deployKYCHook(uint256 kycSalt, uint256 hookSalt) external returns (address hook, address kyc);
    function mineKYCHookAddress(uint256 kycSalt) external view returns (address, uint256);
}

contract KYCHookFactory {
    error ZeroAddress();

    event KYCHookDeployed(address indexed hook, address indexed kyc);

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    constructor(address _superHook, IPoolManager _poolManager) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;
    }

    function deployKYCHook(uint256 kycSalt, uint256 hookSalt) external returns (address hook, address kyc) {
        SimpleKYCContract kycContract = new SimpleKYCContract{salt: bytes32(kycSalt)}(msg.sender);
        kyc = address(kycContract);

        KYCSwaps hookContract = new KYCSwaps{salt: bytes32(hookSalt)}(
            superHook,
            poolManager,
            kyc,
            msg.sender
        );
        hook = address(hookContract);

        emit KYCHookDeployed(hook, kyc);
    }

    function mineKYCHookAddress(uint256 kycSalt) external view returns (address, uint256) {
        bytes memory kycBytecode = abi.encodePacked(
            type(SimpleKYCContract).creationCode,
            abi.encode(msg.sender)
        );

        bytes32 kycHash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                bytes32(kycSalt),
                keccak256(kycBytecode)
            )
        );

        address kycAddress = address(uint160(uint256(kycHash)));

        bytes memory initCode = abi.encodePacked(
            type(KYCSwaps).creationCode,
            abi.encode(superHook, poolManager, kycAddress, msg.sender)
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