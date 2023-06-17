// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionManager} from "./ISubscriptionManager.sol";

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
    // TODO? store subscription contract in manager for validity check

    address private beacon;

    // reference to the Creator contract
    address public creatorContract;

    // owner mapping
    // TODO? move relationship to Creator Token
    mapping(uint256 => address[]) private ownerMapping;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _beacon, address _creatorContract)
        external
        initializer
    {
        beacon = _beacon;
        creatorContract = _creatorContract;
    }

    function createSubscription(
        address _token,
        uint256 _rate,
        uint256 _lock,
        uint256 _epochSize,
        uint256 _creatorTokenId
    ) external returns (address) {
        require(
            IERC721(creatorContract).ownerOf(_creatorTokenId) == _msgSender(),
            "Manager: Not owner of token"
        );

        Subscription implementation = Subscription(
            IBeacon(beacon).implementation()
        );

        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                _token,
                _rate,
                _lock,
                _epochSize,
                creatorContract,
                _creatorTokenId
            )
        );

        address proxyAddress = address(proxy);

        // add contract to owner's list
        ownerMapping[_creatorTokenId].push(proxyAddress);

        emit SubscriptionContractCreated(_creatorTokenId, proxyAddress);

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
