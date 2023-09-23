// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMintAllowedUpgradeable.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

abstract contract MintAllowedUpgradeable is Initializable, ContextUpgradeable, IMintAllowedUpgradeable {
    // tokenId => minterAddress => is allowed to mint
    mapping(uint256 => mapping(address => bool)) private _mintAllowed;

    // tokenId => isFrozen
    mapping(uint256 => bool) private _mintAllowedFrozen;

    function __MintAllowedUpgradeable_init() internal onlyInitializing {
        __MintAllowedUpgradeable_init_unchained();
    }

    function __MintAllowedUpgradeable_init_unchained() internal onlyInitializing {}

    function setMintAllowed(address minter, uint256 id, bool allow) public virtual {
        require(_idExists(id), "MintAllowed: token does not exist");
        require(!isMintAllowedFrozen(id), "MintAllowed: Minter list is frozen");
        _mintAllowed[id][minter] = allow;
    }

    function isMintAllowed(address minter, uint256 id) public view virtual returns (bool) {
        return _mintAllowed[id][minter];
    }

    function freezeMintAllowed(uint256 id) external {
        require(_idExists(id), "MintAllowed: token does not exist");
        _mintAllowedFrozen[id] = true;
    }

    function isMintAllowedFrozen(uint256 id) public view returns (bool) {
        return _mintAllowedFrozen[id];
    }

    function _idExists(uint256 id) internal view virtual returns (bool);

    function _requireMintAllowed(uint256 id) internal view virtual {
        require(isMintAllowed(_msgSender(), id), "MintAllowed: sender not allowed to mint");
    }

    uint256[48] private __gap;
}
