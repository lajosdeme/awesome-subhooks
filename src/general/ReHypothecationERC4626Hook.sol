// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BaseSubHook} from "@superhook/base/BaseSubHook.sol";
import {ReHypothecationHook} from "./ReHypothecationHook.sol";

contract ReHypothecationERC4626Hook is ReHypothecationHook, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    error InvalidVault();
    error VaultAlreadySet();
    error VaultNotSet();

    event VaultSet(Currency indexed currency, address indexed vault);

    mapping(Currency => address) public vaults;

    constructor(
        address _superHook,
        IPoolManager _poolManager,
        address _owner
    ) BaseSubHook(_superHook, _poolManager) ERC20("ReHypothecated-Liquidity", "RHL") Ownable(_owner) {}

    function setVault(Currency currency, address vault) external onlyOwner {
        if (vault == address(0)) revert InvalidVault();
        if (vaults[currency] != address(0)) revert VaultAlreadySet();
        vaults[currency] = vault;
        emit VaultSet(currency, vault);
    }

    function getCurrencyYieldSource(Currency currency) public view override returns (address) {
        return vaults[currency];
    }

    function _depositToYieldSource(Currency currency, uint256 amount) internal override {
        address vault = vaults[currency];
        if (vault == address(0)) revert VaultNotSet();

        IERC20 underlying = IERC20(Currency.unwrap(currency));
        underlying.forceApprove(vault, amount);

        Vault(vault).deposit(amount);
    }

    function _withdrawFromYieldSource(Currency currency, uint256 amount) internal override {
        address vault = vaults[currency];
        if (vault == address(0)) revert VaultNotSet();

        Vault(vault).withdraw(amount, address(this), address(this));
    }

    function _getAmountInYieldSource(Currency currency) internal view override returns (uint256) {
        address vault = vaults[currency];
        if (vault == address(0)) return 0;

        uint256 shares = Vault(vault).balanceOf(address(this));
        return Vault(vault).convertToAssets(shares);
    }

    receive() external payable override {}
}

interface Vault {
    function deposit(uint256 assets) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}