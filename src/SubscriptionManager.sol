// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionManager} from "./ISubscriptionManager.sol";

import {Metadata, SubSettings} from "./subscription/ISubscription.sol";
import {Subscription} from "./subscription/Subscription.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

contract SubscriptionManager is
    ISubscriptionManager,
    Initializable,
    ContextUpgradeable
{
    // TODO deploy block and time based subs?
    // TODO? store subscription contract in manager for validity check -> isManaged()?
    // TODO allow profiles to curate a list of sub contracts

    address private beacon;

    // reference to the Profile contract
    address public profileContract;

    // owner mapping
    // TODO? move relationship to Profile Token
    mapping(uint256 => address[]) private ownerMapping;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _beacon, address _profileContract)
        external
        initializer
    {
        beacon = _beacon;
        profileContract = _profileContract;
    }

    function createSubscription(
        string calldata _name,
        string calldata _symbol,
        Metadata calldata _metadata,
        SubSettings calldata _settings,
        uint256 _profileTokenId
    ) external returns (address) {
        require(
            IERC721(profileContract).ownerOf(_profileTokenId) == _msgSender(),
            "Manager: Not owner of token"
        );

        Subscription implementation = Subscription(
            IBeacon(beacon).implementation()
        );

        // TODO use create2 to prevent users re-using contract addresses on other chains
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                _name,
                _symbol,
                _metadata,
                _settings,
                profileContract,
                _profileTokenId
            )
        );

        address proxyAddress = address(proxy);

        // add contract to owner's list
        ownerMapping[_profileTokenId].push(proxyAddress);

        emit SubscriptionContractCreated(_profileTokenId, proxyAddress);

        return proxyAddress;
    }

    function getSubscriptionContracts(uint256 _ownerTokenId)
        external
        view
        returns (address[] memory)
    {
        return ownerMapping[_ownerTokenId];
    }
}
