// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IProfile is IERC721, IERC721Metadata, IERC721Enumerable {
    event Minted(address indexed to, uint256 indexed tokenId);

    function mint(string memory name, string memory description, string memory image, string memory externalUrl)
        external
        returns (uint256);

    function contractURI() external view returns (string memory);
}
