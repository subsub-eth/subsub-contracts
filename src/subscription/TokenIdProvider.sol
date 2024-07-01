// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract HasTokenIdProvider {
    function _nextTokenId() internal virtual returns (uint256);
}

abstract contract TokenIdProvider is Initializable, HasTokenIdProvider {
    struct TokenIdProviderStorage {
        uint256 _tokenId;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.TokenIdProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TokenIdProviderStorageLocation =
        0x7ef95c70393698ad3167642532ce9f9a4084d997b3cd6e92fc9202fcd2992400;

    function _getTokenIdProviderStorage() private pure returns (TokenIdProviderStorage storage $) {
        assembly {
            $.slot := TokenIdProviderStorageLocation
        }
    }

    function __TokenIdProvider_init(uint256 tokenId) internal onlyInitializing {
        __TokenIdProvider_init_unchained(tokenId);
    }

    function __TokenIdProvider_init_unchained(uint256 tokenId) internal onlyInitializing {
        TokenIdProviderStorage storage $ = _getTokenIdProviderStorage();
        $._tokenId = tokenId;
    }

    function _nextTokenId() internal override returns (uint256) {
        TokenIdProviderStorage storage $ = _getTokenIdProviderStorage();
        $._tokenId++;
        return $._tokenId;
    }
}