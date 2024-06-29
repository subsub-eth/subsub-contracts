// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Subscription Function library
 * @notice Subscription Function library
 * @dev Various functions to help conversions etc. associated with subscriptions
 */
library Lib {
    uint256 public constant MULTIPLIER_BASE = 100;

    uint8 public constant INTERNAL_DECIMALS = 18;

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


    function expiresAt(uint256 amount, uint256 depositedAt, uint256 mRate) internal pure returns (uint256) {
        return depositedAt + (amount / mRate);
    }

    /**
     * @notice calculates the validity of a certain amount (of funds) in relation to the given rate and multiplier
     * @dev calculates the amount of time units a certain amount if valid for
     * @param amount amount of funds
     * @param rate the base rate of a sub scription
     * @param multiplier individual multiplier that is applied to the rate
     * @return the amount of time unit the amount is valid for
     */
    function validFor(uint256 amount, uint256 rate, uint256 multiplier) internal pure returns (uint256) {
      return (amount * MULTIPLIER_BASE) / (rate * multiplier);
    }
}