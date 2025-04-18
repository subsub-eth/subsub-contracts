// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SubscriptionInitialize, MetadataStruct, SubSettings, SubscriptionInitialize} from "../ISubscription.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {DiamondBeaconProxy} from "diamond-beacon/DiamondBeaconProxy.sol";

abstract contract HasFactory {
    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal virtual returns (address);
}

abstract contract DiamondFactory is Initializable, HasFactory {
    // solhint-disable-next-line immutable-vars-naming
    address private immutable _beacon;

    constructor(address beacon) {
        _beacon = beacon;
    }

    // slither-disable-start dead-code
    function __DiamondFactory_init() internal onlyInitializing {
        __DiamondFactory_init_unchained();
    }
    // slither-disable-end dead-code

    // solhint-disable-next-line no-empty-blocks
    function __DiamondFactory_init_unchained() internal onlyInitializing {}

    // deploy a new subscription
    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal virtual override returns (address) {
        // TODO use create2 to prevent users re-using contract addresses on other chains
        DiamondBeaconProxy proxy = new DiamondBeaconProxy(
            _beacon,
            abi.encodeWithSelector(SubscriptionInitialize.initialize.selector, _name, _symbol, _metadata, _settings)
        );

        return address(proxy);
    }
}
