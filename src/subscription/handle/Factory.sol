// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionInitialize, MetadataStruct, SubSettings} from "../ISubscription.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {BeaconProxy} from "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "openzeppelin-contracts/proxy/beacon/IBeacon.sol";

abstract contract HasFactory {
    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal virtual returns (address);
}

abstract contract Factory is Initializable, HasFactory {
    address private immutable _beacon;

    constructor(address beacon) {
        _beacon = beacon;
    }

    function __Factory_init() internal onlyInitializing {
        __Factory_init_unchained();
    }

    function __Factory_init_unchained() internal onlyInitializing {}

    // deploy a new subscription
    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal virtual override returns (address) {
        SubscriptionInitialize implementation = SubscriptionInitialize(IBeacon(_beacon).implementation());

        // TODO use create2 to prevent users re-using contract addresses on other chains
        BeaconProxy proxy = new BeaconProxy(
            _beacon, abi.encodeWithSelector(implementation.initialize.selector, _name, _symbol, _metadata, _settings)
        );

        return address(proxy);
    }
}
