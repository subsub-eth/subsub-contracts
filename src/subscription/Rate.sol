// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lib} from "./Lib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract HasRate {
    function _rate() internal view virtual returns (uint256);
}

abstract contract Rate is Initializable, HasRate {
    using Lib for uint256;

    struct RateStorage {
        uint256 _rate;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.Rate")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RateStorageLocation = 0xe56147cf33567ea17c70c1c3a37ecf7bbea223c6f2347f6e350fdeb3b5396d00;

    function _getRateStorage() private pure returns (RateStorage storage $) {
        assembly {
            $.slot := RateStorageLocation
        }
    }

    function __Rate_init(uint256 rate) internal onlyInitializing {
        __Rate_init_unchained(rate);
    }

    function __Rate_init_unchained(uint256 rate) internal onlyInitializing {
        RateStorage storage $ = _getRateStorage();
        $._rate = rate;
    }

    function _rate() internal view override returns (uint256) {
        RateStorage storage $ = _getRateStorage();
        return $._rate;
    }

    // TODO _gap
}