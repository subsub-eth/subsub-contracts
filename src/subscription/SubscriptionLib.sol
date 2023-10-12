// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library SubscriptionLib {
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

    function adjustToRate(uint256 amount, uint256 rate)
        internal
        pure
        returns (uint256)
    {
        // TODO gas optimization: return amount - (amount % rate);
        return (amount / rate) * rate;
    }


    function expiresAt(uint256 amount, uint256 depositedAt, uint256 mRate) internal pure returns (uint256) {
        return depositedAt + (amount / mRate);
    }

    function multipliedRate(uint256 rate, uint256 multiplier) internal pure returns (uint256) {
        return (rate * multiplier) / MULTIPLIER_BASE;
    }
}
