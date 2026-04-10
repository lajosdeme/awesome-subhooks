// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract SimpleNFT is ERC721, Ownable {
    uint256 private _currentTokenId;

    constructor(string memory name, string memory symbol, address owner) ERC721(name, symbol) Ownable(owner) {}

    function mint(address to) external onlyOwner {
        _currentTokenId++;
        _mint(to, _currentTokenId);
    }
}