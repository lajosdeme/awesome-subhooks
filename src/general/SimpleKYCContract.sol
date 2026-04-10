// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleKYCContract is Ownable {
    error ZeroAddress();
    error AlreadyMinted();

    mapping(address => bool) public hasMinted;

    string public constant name = "KYC Token";
    string public constant symbol = "KYC";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    event Minted(address indexed to);

    constructor(address owner) Ownable(owner) {}

    function mint(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (hasMinted[to]) revert AlreadyMinted();
        
        hasMinted[to] = true;
        balanceOf[to] = 1;
        totalSupply += 1;
        
        emit Minted(to);
    }

    function hasValidToken(address _addr) external view returns (bool) {
        return balanceOf[_addr] >= 1;
    }
}