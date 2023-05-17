// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import "forge-std/console.sol";

// TODO add meta information, name, links, etc
// TODO max supply?
contract Creator is ERC721Upgradeable {
    uint256 public totalSupply;

    constructor() {
        // disable direct usage of implementation contract
        _disableInitializers();
    }

    function initialize() public initializer {
        // TODO rename
        __ERC721_init("Creator", "CRE");
    }

    function mint() external returns (uint256) {
        uint256 tokenId = ++totalSupply;

        _safeMint(_msgSender(), tokenId);
        return tokenId;
    }
}
