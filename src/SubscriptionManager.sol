// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionManager} from "./ISubscriptionManager.sol";
import {HasFactory, Factory} from "./manager/Factory.sol";

import {MetadataStruct, SubSettings} from "./subscription/ISubscription.sol";
import {Subscription} from "./subscription/Subscription.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

abstract contract SubscriptionManager is
    Initializable,
    ContextUpgradeable,
    HasFactory,
    ERC721EnumerableUpgradeable,
    ISubscriptionManager
{
    // TODO deploy block and time based subs?
    // TODO? store subscription contract in manager for validity check -> isManaged()?

    function mint(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external returns (address) {

      address addr = _deploySubscription(_name, _symbol, _metadata, _settings);

      uint256 tokenId = uint256(uint160(addr));
      _safeMint(_msgSender(), tokenId);

      emit SubscriptionContractCreated(tokenId, addr);
      return addr;
    }

    function register(address _contract) external {
      revert("not implemented");
    }
}

contract DefaultSubscriptionManager is SubscriptionManager, Factory {

    constructor() {
        _disableInitializers();
    }

    function initialize(address beacon) external initializer {
        __Factory_init_unchained(beacon);
        __Context_init_unchained();
        __ERC721Enumerable_init_unchained();
    }

}
