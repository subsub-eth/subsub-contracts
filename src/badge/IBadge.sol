// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMintAllowedUpgradeable} from "../IMintAllowedUpgradeable.sol";

import {IERC1155Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/IERC1155Upgradeable.sol";
import {IERC1155MetadataURIUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/extensions/IERC1155MetadataURIUpgradeable.sol";

struct TokenData {
    string name;
    uint256 maxSupply;
}

interface IBadge is IERC1155Upgradeable, IERC1155MetadataURIUpgradeable, IMintAllowedUpgradeable{
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;

    // TODO batchMint???

    function burn(uint256 id, uint256 amount) external;

    // contract owner can create new tokens
    function createToken(TokenData memory tokenData) external returns (uint256);

    // TODO edit token data?

}