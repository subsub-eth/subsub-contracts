// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SubLib} from "./SubLib.sol";

import {OzInitializable} from "../dependency/OzInitializable.sol";

library RateLib {
    using SubLib for uint256;

    struct RateStorage {
        uint256 _rate;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.Rate")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant RateStorageLocation = 0xa2ca329117191c395efb155f9beaf3d27ba875c24fb30d77820ec645ca882b00;

    function _getRateStorage() private pure returns (RateStorage storage $) {
        // solhint-disable no-inline-assembly
        assembly {
            $.slot := RateStorageLocation
        }
        // solhint-enable no-inline-assembly
    }

    function init(uint256 rate_) internal {
        RateStorage storage $ = _getRateStorage();
        $._rate = rate_;
    }

    function rate() internal view returns (uint256) {
        RateStorage storage $ = _getRateStorage();
        return $._rate;
    }
}

abstract contract HasRate {
    function _rate() internal view virtual returns (uint256);
}

abstract contract Rate is OzInitializable, HasRate {
    // slither-disable-start dead-code
    function __Rate_init(uint256 rate) internal {
        __Rate_init_unchained(rate);
    }
    // slither-disable-end dead-code

    function __Rate_init_unchained(uint256 rate) internal {
        __checkInitializing();
        RateLib.init(rate);
    }

    function _rate() internal view override returns (uint256) {
        return RateLib.rate();
    }
}
