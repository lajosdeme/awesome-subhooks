// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721OwnershipHook} from "../awesome-hooks/ERC721OwnershipHook.sol";

import {HookMiner} from "../utils/HookMiner.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

import {SimpleNFT} from "./SimpleNFT.sol";

interface IERC721HookFactory {
    function deployERC721OwnershipHook(
        uint256 erc721Salt,
        uint256 hookSalt,
        string memory name,
        string memory symbol
    ) external returns (address hook, address nft);

    function mineERC721HookAddress(
        uint256 erc721Salt,
        string memory name,
        string memory symbol
    ) external view returns (address, uint256);
}
contract ERC721HookFactory {
    error ZeroAddress();

    event ERC721OwnershipHookDeployed(
        address indexed hook,
        address indexed nft
    );

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    constructor(address _superHook, IPoolManager _poolManager) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;
    }

    function deployERC721OwnershipHook(
        uint256 erc721Salt,
        uint256 hookSalt,
        string memory name,
        string memory symbol
    ) external returns (address hook, address nft) {
        SimpleNFT nftContract = new SimpleNFT{salt: bytes32(erc721Salt)}(
            name,
            symbol,
            msg.sender
        );
        nft = address(nftContract);

        ERC721OwnershipHook hookContract = new ERC721OwnershipHook{
            salt: bytes32(hookSalt)
        }(superHook, poolManager, nftContract);
        hook = address(hookContract);

        emit ERC721OwnershipHookDeployed(hook, nft);
    }

    function mineERC721HookAddress(
        uint256 erc721Salt,
        string memory name,
        string memory symbol
    ) external view returns (address, uint256) {
        bytes memory bytecode = abi.encodePacked(
            type(SimpleNFT).creationCode,
            abi.encode(name, symbol, msg.sender)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                bytes32(erc721Salt),
                keccak256(bytecode)
            )
        );

        address nftAddress = address(uint160(uint256(hash)));

        bytes memory initCode = abi.encodePacked(
            type(ERC721OwnershipHook).creationCode,
            abi.encode(superHook, poolManager, nftAddress)
        );

        uint160 mask = HookMiner.permissionsToMask(
            false,
            false,
            false,
            false,
            false,
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
