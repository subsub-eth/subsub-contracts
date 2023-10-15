// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract HasPaymentToken {
    function _paymentToken() internal view virtual returns (IERC20Metadata);

    function _decimals() internal view virtual returns (uint8);
}

abstract contract PaymentToken is Initializable, HasPaymentToken {
    struct PaymentTokenStorage {
        IERC20Metadata _paymentToken;
        uint8 _decimals;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.PaymentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PaymentTokenStorageLocation =
        0x6f5829cd7e76089adec788013c8fec4384896d2139d3621f34813ccb0ad48d00;

    function _getPaymentTokenStorage() private pure returns (PaymentTokenStorage storage $) {
        assembly {
            $.slot := PaymentTokenStorageLocation
        }
    }

    function __PaymentToken_init(IERC20Metadata token) internal onlyInitializing {
        __PaymentToken_init_unchained(token);
    }

    function __PaymentToken_init_unchained(IERC20Metadata token) internal onlyInitializing {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        $._paymentToken = token;
        $._decimals = token.decimals();
    }

    function _paymentToken() internal view override returns (IERC20Metadata) {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        return $._paymentToken;
    }

    function _decimals() internal view override returns (uint8) {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        return $._decimals;
    }
}
