// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionLib} from "./SubscriptionLib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract HasRate {
    function _multipliedRate(uint256 multiplier) internal view virtual returns (uint256);

    function _rate() internal view virtual returns (uint256);
}

abstract contract Rate is Initializable, HasRate {
    using SubscriptionLib for uint256;

    uint256 private __rate;

    function __Rate_init(uint256 rate) internal onlyInitializing {
        __Rate_init_unchained(rate);
    }

    function __Rate_init_unchained(uint256 rate) internal onlyInitializing {
        __rate = rate;
    }

    function _multipliedRate(uint256 multiplier) internal view override returns (uint256) {
        // TODO check gas consumption
        return __rate.multipliedRate(multiplier);
    }

    function _rate() internal view override returns (uint256) {
        return __rate;
    }

    // TODO _gap
}
