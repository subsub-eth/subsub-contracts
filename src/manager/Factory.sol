// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionInitialize, MetadataStruct, SubSettings} from "../subscription/ISubscription.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

abstract contract HasFactory {
    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal virtual returns (address);
}

abstract contract Factory is Initializable, HasFactory {
    struct FactoryStorage {
        address _beacon;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.manager.Factory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FactoryStorageLocation = 0xfaab449ce6ae6b64b8e8791cb54a47fdcd59089e77337ddf9f0e70677c57c000;

    function _getFactoryStorage() private pure returns (FactoryStorage storage $) {
        assembly {
            $.slot := FactoryStorageLocation
        }
    }

    function __Factory_init(address beacon) internal onlyInitializing {
        __Factory_init_unchained(beacon);
    }

    function __Factory_init_unchained(address beacon) internal onlyInitializing {
        FactoryStorage storage $ = _getFactoryStorage();
        $._beacon = beacon;
    }

    // deploy a new subscription
    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal virtual override returns (address) {
        FactoryStorage storage $ = _getFactoryStorage();

        SubscriptionInitialize implementation = SubscriptionInitialize(IBeacon($._beacon).implementation());

        // TODO use create2 to prevent users re-using contract addresses on other chains
        BeaconProxy proxy = new BeaconProxy(
            $._beacon,
            abi.encodeWithSelector(
                implementation.initialize.selector,
                _name,
                _symbol,
                _metadata,
                _settings
            )
        );

        return address(proxy);
    }
}
