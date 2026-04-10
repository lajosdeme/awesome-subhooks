// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockToken is ERC20, Ownable {
    address public immutable minter;

    error NotMinter();

    constructor(
        string memory name,
        string memory symbol,
        address owner
    ) ERC20(name, symbol) Ownable(owner) {
        minter = msg.sender;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (msg.sender != minter) revert NotMinter();
        _mint(to, amount);
    }
}