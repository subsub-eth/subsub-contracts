// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import {MetadataStruct, SubSettings} from "./subscription/ISubscription.sol";

// tokenID == address(subscriptionContract)
// TODO add comments
interface SubscriptionManagerEvents {
    event SubscriptionContractCreated(uint256 indexed ownerTokenId, address indexed contractAddress);
}

interface SubscriptionFactory is SubscriptionManagerEvents {
    // deploy a new subscription
    function mint(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external returns (address);

    // register an existing implementation
    function register(address _contract) external;
}

interface ISubscriptionManager is SubscriptionFactory, IERC721Enumerable {}
