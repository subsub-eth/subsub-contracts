// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";
import {IERC721MetadataUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {IERC721EnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

interface IProfile is
    IERC721Upgradeable,
    IERC721MetadataUpgradeable,
    IERC721EnumerableUpgradeable
{
    function mint(
        string memory name,
        string memory description,
        string memory image,
        string memory externalUrl
    ) external returns (uint256);

    function contractURI() external view returns (string memory);
}
