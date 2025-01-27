// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

// solhint-disable-next-line no-empty-blocks
interface IBadgeHandle is BadgeFactory, HasManagingHandle, IERC721Enumerable {}
