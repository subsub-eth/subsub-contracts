// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";
import {IERC721MetadataUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";

import {MetadataStruct, SubSettings} from "./subscription/ISubscription.sol";

// TODO add comments
interface SubscriptionManagerEvents {
    // add more values?
    event SubscriptionContractCreated(
        uint256 indexed ownerTokenId,
        address indexed contractAddress
    );
}

interface ISubscriptionManager is SubscriptionManagerEvents {
    function profileContract() external returns (address);

    function getSubscriptionContracts(uint256 _ownerTokenId)
        external
        view
        returns (address[] memory);

    function createSubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings,
        uint256 _creatorTokenId
    ) external returns (address);
}
