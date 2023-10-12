// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionLib} from "./SubscriptionLib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract HasPaymentToken {

    function _paymentToken() internal virtual view returns (IERC20Metadata);

    function _decimals() internal virtual view returns (uint8);
}

abstract contract PaymentToken is Initializable, HasPaymentToken {

    IERC20Metadata private __paymentToken;
    uint8 private __decimals;

    function __PaymentToken_init(IERC20Metadata token) internal onlyInitializing {
        __PaymentToken_init_unchained(token);
    }

    function __PaymentToken_init_unchained(IERC20Metadata token) internal onlyInitializing {
      __paymentToken = token;
      __decimals = token.decimals();
    }

    function _paymentToken() internal override view returns (IERC20Metadata) {
      return __paymentToken;
    }

    function _decimals() internal override view returns (uint8) {
      return __decimals;
    }

    // TODO _gap
}

