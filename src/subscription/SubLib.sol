// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// TODO optimize validFor + expiresAt with applied multiplier
/**
 * @title Subscription Function library
 * @notice Subscription Function library
 * @dev Various functions to help conversions etc. associated with subscriptions
 */
library SubLib {
    uint24 internal constant MULTIPLIER_BASE = 100;
    uint24 internal constant MULTIPLIER_MAX = 10_000;

    uint24 internal constant LOCK_BASE = 10_000; // == 100%

    uint8 internal constant INTERNAL_DECIMALS = 18;

    function toInternal(uint256 externalAmount, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        uint256 internalAmount;

        if (tokenDecimals < INTERNAL_DECIMALS) {
            uint8 x = INTERNAL_DECIMALS - tokenDecimals;
            internalAmount = externalAmount * (10**x);
        } else if (tokenDecimals > INTERNAL_DECIMALS) {
            uint8 x = tokenDecimals - INTERNAL_DECIMALS;
            internalAmount = externalAmount / (10**x);
        } else {
            // token has 18 decimals
            internalAmount = externalAmount;
        }
        return internalAmount;
    }

    function toExternal(uint256 internalAmount, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        uint256 externalAmount;

        if (tokenDecimals < INTERNAL_DECIMALS) {
            uint8 x = INTERNAL_DECIMALS - tokenDecimals;
            externalAmount = internalAmount / (10**x);
        } else if (tokenDecimals > INTERNAL_DECIMALS) {
            uint8 x = tokenDecimals - INTERNAL_DECIMALS;
            externalAmount = internalAmount * (10**x);
        } else {
            // token has 18 decimals
            externalAmount = internalAmount;
        }
        return externalAmount;
    }


    /**
     * @notice calculates the expiration date of a multiplied amount of funds based on the deposit date and the multiplied rate
     * @param mAmount multiplied amount of funds
     * @param depositedAt the deposit date
     * @param mRate the multiplied rate of a sub
     * @return the date the subscription expires (excluding)
     */
    function expiresAt(uint256 mAmount, uint256 depositedAt, uint256 mRate) internal pure returns (uint256) {
        return depositedAt + (mAmount / mRate);
    }

    /**
     * @notice calculates the expiration date of an amount of funds based on the deposit date, the rate, and the multiplier
     * @param amount amount of funds
     * @param depositedAt the deposit date
     * @param rate the rate of the contract
     * @param multiplier the multiplier of a sub
     * @return the date the subscription expires (excluding)
     */
    function expiresAt(uint256 amount, uint256 depositedAt, uint256 rate, uint24 multiplier) internal pure returns (uint256) {
        return depositedAt + validFor(amount, rate, multiplier);
    }

    /**
     * @notice calculates the validity of a certain amount (of funds) in relation to the given rate and multiplier
     * @dev calculates the amount of time units a certain amount if valid for
     * @param amount amount of funds
     * @param rate the base rate of a sub scription
     * @param multiplier individual multiplier that is applied to the rate
     * @return the amount of time unit the amount is valid for
     */
    function validFor(uint256 amount, uint256 rate, uint24 multiplier) internal pure returns (uint256) {
      return (amount * MULTIPLIER_BASE) / (rate * multiplier);
    }

    /**
     * @notice calculates the locked percentage of a given amount
     * @param amount amount of funds
     * @param lock the locked percentage
     * @return the amount of locked funds
     */
    function asLocked(uint256 amount, uint24 lock) internal pure returns (uint256) {
      return (amount * lock) / LOCK_BASE;
    }

    /**
     * @notice calculates the epoch of a given time unit and the size of epochs
     * @param time the point in time
     * @param epochSize the size of epochs
     * @return the epoch
     */
    function epochOf(uint256 time, uint256 epochSize) internal pure returns (uint256) {
        return time / epochSize;
    }


}