// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionLib} from "./SubscriptionLib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract SubscriptionCore is Initializable {
    using SubscriptionLib for uint256;

    uint256 private _rate;

    function __SubscriptionCore_init(uint256 rate) internal onlyInitializing {
        __SubscriptionCore_init_unchained(rate);
    }

    function __SubscriptionCore_init_unchained(uint256 rate) internal onlyInitializing {
        _rate = rate;
    }

    function _multipliedRate(uint256 multiplier) internal view returns (uint256) {
        // TODO check gas consumption
        return _rate.multipliedRate(multiplier);
    }

    // TODO _gap
}
