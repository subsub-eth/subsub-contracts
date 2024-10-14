// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubLib} from "./SubLib.sol";

import {HasPaymentToken} from "./PaymentToken.sol";

library BaseSubscriptionLib {}

/**
 * @notice Provides base functions needed throughout other subscription modules
 */
abstract contract HasBaseSubscription {
    /**
     * @notice converts an mount to the internal representation
     * @param amount the external representation
     * @return the internal representation
     *
     */
    function _asInternal(uint256 amount) internal view virtual returns (uint256);

    /**
     * @notice converts an mount to the internal representation
     * @param amount the internal representation
     * @return the external representation
     *
     */
    function _asExternal(uint256 amount) internal view virtual returns (uint256);
}

abstract contract BaseSubscription is HasBaseSubscription, HasPaymentToken {
    using SubLib for uint256;

    function _asInternal(uint256 amount) internal view virtual override returns (uint256) {
        return amount.toInternal(_decimals());
    }

    function _asExternal(uint256 amount) internal view virtual override returns (uint256) {
        return amount.toExternal(_decimals());
    }
}
