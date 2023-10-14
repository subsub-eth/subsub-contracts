// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMintAllowedUpgradeable} from "../IMintAllowedUpgradeable.sol";

import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155MetadataURI} from
    "openzeppelin-contracts/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

struct TokenData {
    string name;
    uint256 maxSupply;
}

interface IBadgeEvents {
    event TokenCreated(address indexed creator, uint256 tokenId);
}

interface IBadgeOperations {
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;

    function burn(address account, uint256 id, uint256 value) external;

    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) external;
}

interface IBadgeCreation {
    // contract owner can create new tokens
    function createToken(TokenData memory tokenData) external returns (uint256);

    // TODO edit token data?
}

interface IBadge is
    IERC1155,
    IERC1155MetadataURI,
    IMintAllowedUpgradeable,
    IBadgeEvents,
    IBadgeOperations,
    IBadgeCreation
{}
