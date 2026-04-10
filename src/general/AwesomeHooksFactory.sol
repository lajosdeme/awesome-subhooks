// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";

import {IWhitelistHookFactory} from "../factories/WhitelistHookFactory.sol";
import {IKYCHookFactory} from "../factories/KYCHookFactory.sol";
import {IMultiSigSwapHookFactory} from "../factories/MultiSigSwapHookFactory.sol";
import {IVotingEscrowHookFactory} from "../factories/VotingEscrowHookFactory.sol";
import {IRehypothecationERC4626HookFactory} from "../factories/RehypothecationERC4626HookFactory.sol";
import {IERC721HookFactory} from "../factories/ERC721HookFactory.sol";

import {SimpleNFT} from "../factories/SimpleNFT.sol";
import {SimpleKYCContract} from "./SimpleKYCContract.sol";

// -------------------------------------------------------------------------
// AwesomeHooksFactory - Router to sub-factories
// -------------------------------------------------------------------------

contract AwesomeHooksFactory {
    error ZeroAddress();
    error NotImplemented();

    event ERC721OwnershipHookDeployed(
        address indexed hook,
        address indexed nft
    );
    event KYCHookDeployed(address indexed hook, address indexed kyc);
    event MultiSigSwapHookDeployed(address indexed hook);
    event VotingEscrowHookDeployed(address indexed hook);
    event WhitelistHookDeployed(address indexed hook);
    event ReHypothecationERC4626HookDeployed(address indexed hook);

    address public immutable superHook;
    IPoolManager public immutable poolManager;

    // Sub-factory addresses
    address public immutable whitelistHookFactory;
    address public immutable kycHookFactory;
    address public immutable multiSigSwapHookFactory;
    address public immutable votingEscrowHookFactory;
    address public immutable rehypothecationERC4626HookFactory;
    address public immutable erc721HookFactory;

    mapping(address => bool) public isERC721Hook;
    mapping(address => bool) public isKYCHook;
    mapping(address => bool) public isMultiSigSwapHook;
    mapping(address => bool) public isVotingEscrowHook;
    mapping(address => bool) public isWhitelistHook;
    mapping(address => bool) public isReHypothecationERC4626Hook;

    mapping(address => address) public kycContractForHook;
    mapping(address => address) public nftContractForHook;

    constructor(
        address _superHook,
        IPoolManager _poolManager,
        address[] memory factoryAddresses
    ) {
        if (_superHook == address(0)) revert ZeroAddress();
        superHook = _superHook;
        poolManager = _poolManager;

        whitelistHookFactory = factoryAddresses[0];
        kycHookFactory = factoryAddresses[1];
        multiSigSwapHookFactory = factoryAddresses[2];
        votingEscrowHookFactory = factoryAddresses[3];
        rehypothecationERC4626HookFactory = factoryAddresses[4];
        erc721HookFactory = factoryAddresses[5];
    }

    // -------------------------------------------------------------------------
    // Deployers - Delegate to sub-factories
    // -------------------------------------------------------------------------

    function deployWhitelistHook(uint256 salt) external returns (address hook) {
        hook = IWhitelistHookFactory(whitelistHookFactory).deployWhitelistHook(salt);
        isWhitelistHook[hook] = true;
        emit WhitelistHookDeployed(hook);
    }

    function deployKYCHook(uint256 kycSalt, uint256 hookSalt) external returns (address hook, address kyc) {
        (hook, kyc) = IKYCHookFactory(kycHookFactory).deployKYCHook(kycSalt, hookSalt);
        isKYCHook[hook] = true;
        kycContractForHook[hook] = kyc;
        emit KYCHookDeployed(hook, kyc);
    }

    function deployMultiSigSwapHook(
        uint256 salt,
        address[] memory signers,
        uint256 requiredSignatures
    ) external returns (address hook) {
        hook = IMultiSigSwapHookFactory(multiSigSwapHookFactory).deployMultiSigSwapHook(
            salt,
            signers,
            requiredSignatures
        );
        isMultiSigSwapHook[hook] = true;
        emit MultiSigSwapHookDeployed(hook);
    }

    function deployVotingEscrowHook(
        uint256 tokenSalt,
        uint256 hookSalt,
        string memory name,
        string memory symbol
    ) external returns (address hook) {
        hook = IVotingEscrowHookFactory(votingEscrowHookFactory).deployVotingEscrowHook(
            tokenSalt,
            hookSalt,
            name,
            symbol
        );
        isVotingEscrowHook[hook] = true;
        emit VotingEscrowHookDeployed(hook);
    }

    function deployERC721OwnershipHook(
        uint256 erc721Salt,
        uint256 hookSalt,
        string memory name,
        string memory symbol
    ) external returns (address hook, address nft) {
        (hook, nft) = IERC721HookFactory(erc721HookFactory).deployERC721OwnershipHook(
            erc721Salt,
            hookSalt,
            name,
            symbol
        );
        isERC721Hook[hook] = true;
        nftContractForHook[hook] = nft;
        emit ERC721OwnershipHookDeployed(hook, nft);
    }

    function deployReHypothecationERC4626Hook(uint256 salt) external returns (address hook) {
        hook = IRehypothecationERC4626HookFactory(rehypothecationERC4626HookFactory).deployRehypothecationERC4626Hook(salt);
        isReHypothecationERC4626Hook[hook] = true;
        emit ReHypothecationERC4626HookDeployed(hook);
    }

    // -------------------------------------------------------------------------
    // Miners - Delegate to sub-factories
    // -------------------------------------------------------------------------

    function mineWhitelistHookAddress()
        external
        view
        returns (address, uint256)
    {
        return IWhitelistHookFactory(whitelistHookFactory).mineWhitelistHookAddress();
    }

    function mineKYCHookAddress(uint256 kycSalt)
        external
        view
        returns (address, uint256)
    {
        return IKYCHookFactory(kycHookFactory).mineKYCHookAddress(kycSalt);
    }

    function mineMultiSigSwapHookAddress(
        address[] memory signers,
        uint256 requiredSignatures
    ) external view returns (address, uint256) {
        return IMultiSigSwapHookFactory(multiSigSwapHookFactory).mineMultiSigSwapHookAddress(
            signers,
            requiredSignatures
        );
    }

    function mineVotingEscrowHookAddress(
        uint256 tokenSalt,
        string memory name,
        string memory symbol
    ) external view returns (address, uint256) {
        return IVotingEscrowHookFactory(votingEscrowHookFactory).mineVotingEscrowHookAddress(
            tokenSalt,
            name,
            symbol
        );
    }

    function mineERC721HookAddress(
        uint256 erc721Salt,
        string memory name,
        string memory symbol
    ) external view returns (address, uint256) {
        return IERC721HookFactory(erc721HookFactory).mineERC721HookAddress(
            erc721Salt,
            name,
            symbol
        );
    }

    function mineRehypothecationERC4626HookAddress()
        external
        view
        returns (address, uint256)
    {
        return IRehypothecationERC4626HookFactory(rehypothecationERC4626HookFactory).mineRehypothecationERC4626HookAddress();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function mintNFT(address hook, address to) external {
        if (!isERC721Hook[hook]) revert NotERC721Hook();
        SimpleNFT nft = SimpleNFT(nftContractForHook[hook]);
        nft.mint(to);
    }

    function mintKYCToken(address hook, address to) external {
        if (!isKYCHook[hook]) revert NotKYCHook();
        SimpleKYCContract kyc = SimpleKYCContract(kycContractForHook[hook]);
        kyc.mint(to);
    }

    error NotERC721Hook();
    error NotKYCHook();
}