// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import "forge-std/console.sol";

// TODO change token id generation
// TODO list tokens of user X
// TODO add meta information, name, links, etc
// TODO max supply?
// TODO bind to another ERC721 for identity verification
contract Creator is ERC721Upgradeable {
    event Minted(address indexed to, uint256 indexed tokenId);

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

        emit Minted(_msgSender(), tokenId);

        return tokenId;
    }
}
