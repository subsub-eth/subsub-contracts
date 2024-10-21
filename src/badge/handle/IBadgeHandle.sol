// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import {HasManagingHandle} from "../../handle/ManagingHandle.sol";

// tokenID == address(subscriptionContract)
// TODO add comments
interface BadgeHandleEvents {
    event BadgeContractCreated(uint256 indexed ownerTokenId, address indexed contractAddress);
}

interface BadgeFactory is BadgeHandleEvents {
    // deploy a new badge
    // TODO pass URI
    function mint() external returns (address);
}

interface IBadgeHandle is BadgeFactory, HasManagingHandle, IERC721Enumerable {}
