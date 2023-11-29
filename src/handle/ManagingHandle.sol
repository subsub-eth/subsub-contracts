// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

import {HasContractRegistry} from "./ContractRegistry.sol";

interface HasManagingHandle {
    // register an existing implementation
    function register(address _contract) external returns (uint256);

    function isManaged(uint256 tokenId) external view returns (bool);

    function contractOf(uint256 tokenId) external view returns (address);
}

abstract contract ManagingHandle is HasManagingHandle, ContextUpgradeable, HasContractRegistry {
    function register(address _contract) external virtual returns (uint256) {
        require(_addToRegistry(_contract, false), "Handle: Contract already added");

        uint256 tokenId = uint256(uint160(_contract));
        _safeMint(_msgSender(), tokenId, "");

        return tokenId;
    }

    function isManaged(uint256 tokenId) external view virtual returns (bool) {
        require(tokenId <= type(uint160).max, "Handle: Id too large");

        address addr = address(uint160(tokenId));
        return _isManaged(addr);
    }

    function contractOf(uint256 tokenId) external view returns (address) {
        require(tokenId <= type(uint160).max, "Handle: Id too large");

        address addr = address(uint160(tokenId));

        require(_isRegistered(addr), "Handle: not registered");

        return addr;
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual;
}
