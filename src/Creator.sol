// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721EnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {CountersUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/CountersUpgradeable.sol";

import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import "forge-std/console.sol";

// TODO change token id generation
// TODO add burn
// TODO add gap?
// TODO fix supportsInterface
// TODO add meta information, name, links, etc
// TODO max supply?
// TODO bind to another ERC721 for identity verification
contract Creator is ERC721EnumerableUpgradeable {
    event Minted(address indexed to, uint256 indexed tokenId);

    using Strings for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenIdTracker;

    constructor() {
        // disable direct usage of implementation contract
        _disableInitializers();
    }

    function initialize() public initializer {
        // TODO rename
        __ERC721_init("Creator", "CRE");
    }

    function mint() external returns (uint256) {
        _tokenIdTracker.increment();
        uint256 tokenId = _tokenIdTracker.current();

        _safeMint(_msgSender(), tokenId);

        emit Minted(_msgSender(), tokenId);

        return tokenId;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        _requireMinted(tokenId);

        string memory output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Creator: ',
                        tokenId.toString(),
                        '", "description": "Creator token"',
                        '}'
                    )
                )
            )
        );

        output = string(
            abi.encodePacked("data:application/json;base64,", output)
        );

        return output;
    }
}
