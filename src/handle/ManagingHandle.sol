// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

import {HasContractRegistry} from "./ContractRegistry.sol";

interface HasManagingHandle {
    // register an existing implementation
    function register(address _contract) external;

    function isManaged(uint256 tokenId) external view returns (bool);
}

abstract contract ManagingHandle is HasManagingHandle, ContextUpgradeable, HasContractRegistry {
    function register(address _contract) external virtual {
        require(_addToRegistry(_contract, false), "Handle: Contract already added");

        uint256 tokenId = uint256(uint160(_contract));
        _safeMint(_msgSender(), tokenId, "");
    }

    function isManaged(uint256 tokenId) external virtual view returns (bool) {
        if (tokenId > type(uint160).max) {
            return false;
        }
        address addr = address(uint160(tokenId));
        return _isManaged(addr);
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual;
}
