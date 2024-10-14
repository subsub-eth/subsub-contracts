// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

import {IBadgeInitialize} from "../IBadge.sol";

abstract contract HasFactory {
    function _deployBadge() internal virtual returns (address);
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

    // deploy a new badge
    function _deployBadge() internal virtual override returns (address) {
        IBadgeInitialize implementation = IBadgeInitialize(IBeacon(_beacon).implementation());

        BeaconProxy proxy = new BeaconProxy(_beacon, abi.encodeWithSelector(implementation.initialize.selector));

        return address(proxy);
    }
}
