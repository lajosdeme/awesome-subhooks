// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract SimpleERC4626Vault is ERC4626, Ownable {

    error ZeroAddress();
    error DepositTooSmall();

    uint256 public constant MIN_INITIAL_DEPOSIT = 1000;

    mapping(address => bool) public isAllowedCaller;

    event CallerAllowed(address indexed caller, bool allowed);

    modifier onlyAllowedCaller() {
        require(isAllowedCaller[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address owner
    ) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) Ownable(owner) {
        if (_asset == address(0)) revert ZeroAddress();
    }

    function setAllowedCaller(address _caller, bool _allowed) external onlyOwner {
        isAllowedCaller[_caller] = _allowed;
        emit CallerAllowed(_caller, _allowed);
    }

    function deposit(uint256 assets, address receiver) public override onlyAllowedCaller returns (uint256) {
        if (totalSupply() > 0 && assets < MIN_INITIAL_DEPOSIT) revert DepositTooSmall();
        return super.deposit(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        onlyAllowedCaller
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function mint(uint256 shares, address receiver) public override onlyAllowedCaller returns (uint256) {
        return super.mint(shares, receiver);
    }
}