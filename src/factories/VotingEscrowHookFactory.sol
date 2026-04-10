// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotingEscrow} from "../awesome-hooks/VotingEscrowHook.sol";
import {MockToken} from "../utils/MockToken.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

interface IVotingEscrowHookFactory {
    function deployVotingEscrowHook(
        uint256 tokenSalt,
        uint256 hookSalt,
        string memory name,
        string memory symbol
    ) external returns (address hook);
    function mineVotingEscrowHookAddress(
        uint256 tokenSalt,
        string memory name,
        string memory symbol
    ) external view returns (address, uint256);
}

contract VotingEscrowHookFactory {
    error ZeroAddress();

    event VotingEscrowHookDeployed(address indexed hook);

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    constructor(address _superHook, IPoolManager _poolManager) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;
    }

    function deployVotingEscrowHook(
        uint256 tokenSalt,
        uint256 hookSalt,
        string memory name,
        string memory symbol
    ) external returns (address hook) {
        MockToken token = new MockToken{salt: bytes32(tokenSalt)}(name, symbol, msg.sender);
        
        VotingEscrow hookContract = new VotingEscrow{salt: bytes32(hookSalt)}(
            superHook,
            poolManager,
            address(token),
            name,
            symbol
        );
        hook = address(hookContract);

        emit VotingEscrowHookDeployed(hook);
    }

    function mineVotingEscrowHookAddress(
        uint256 tokenSalt,
        string memory name,
        string memory symbol
    ) external view returns (address, uint256) {
        bytes memory tokenBytecode = abi.encodePacked(
            type(MockToken).creationCode,
            abi.encode(name, symbol, msg.sender)
        );

        bytes32 tokenHash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                bytes32(tokenSalt),
                keccak256(tokenBytecode)
            )
        );

        address tokenAddress = address(uint160(uint256(tokenHash)));

        bytes memory initCode = abi.encodePacked(
            type(VotingEscrow).creationCode,
            abi.encode(superHook, poolManager, tokenAddress, name, symbol)
        );

        uint160 mask = HookMiner.permissionsToMask(
            false,
            true,
            true,
            true,
            true,
            true,
            false,
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