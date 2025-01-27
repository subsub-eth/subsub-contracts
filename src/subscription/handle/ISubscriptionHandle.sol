// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import {MetadataStruct, SubSettings} from "../ISubscription.sol";
import {HasManagingHandle} from "../../handle/ManagingHandle.sol";

// tokenID == address(subscriptionContract)
// TODO add comments
interface SubscriptionHandleEvents {
    event SubscriptionContractCreated(uint256 indexed ownerTokenId, address indexed contractAddress);
}

interface SubscriptionFactory is SubscriptionHandleEvents {
    // deploy a new subscription
    function mint(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external returns (address);
}

// solhint-disable-next-line no-empty-blocks
interface ISubscriptionHandle is SubscriptionFactory, HasManagingHandle, IERC721Enumerable {}