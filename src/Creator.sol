// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import "forge-std/console.sol";

// TODO add meta information, name, links, etc
// TODO max supply?
contract Creator is ERC721 {
    uint256 public totalSupply;

    // TODO rename
    constructor() ERC721("Creator", "CRE") {}

    function mint() external returns (uint256) {
        uint256 tokenId = ++totalSupply;

        _safeMint(_msgSender(), tokenId);
        return tokenId;
    }
}
