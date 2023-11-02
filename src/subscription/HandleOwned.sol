// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

interface HandleOwnedErrors {
    error UnauthorizedAccount(address account);
}

abstract contract HasHandleOwned is HandleOwnedErrors {

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view virtual;

    function owner() public view virtual returns (address);
}

abstract contract HandleOwned is ContextUpgradeable, HasHandleOwned {
    address private immutable _handleContract;

    constructor(address handleContract) {
        _handleContract = handleContract;
    }

    function _checkOwner() internal view override {
        if (owner() != _msgSender()) {
            revert UnauthorizedAccount(_msgSender());
        }
    }

    function owner() public view override returns (address) {
        return IERC721(_handleContract).ownerOf(uint256(uint160(address(this))));
    }
}
