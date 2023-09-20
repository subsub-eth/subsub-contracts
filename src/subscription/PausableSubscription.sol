// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract PausableSubscription is Initializable, ContextUpgradeable {
    event MintingPaused(address account);
    event MintingUnpaused(address account);
    event RenewalPaused(address account);
    event RenewalUnpaused(address account);
    event TippingPaused(address account);
    event TippingUnpaused(address account);

    bool private _mintingPaused;
    bool private _renewalPaused;
    bool private _tippingPaused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __PausableSubscription_init() internal onlyInitializing {
        __PausableSubscription_init_unchained();
    }

    function __PausableSubscription_init_unchained() internal onlyInitializing {
        _mintingPaused = false;
        _renewalPaused = false;
        _tippingPaused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the minting is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenMintingNotPaused() {
        _requireMintingNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the renewal is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenRenewalNotPaused() {
        _requireRenewalNotPaused();
        _;
    }
    /**
     * @dev Modifier to make a function callable only when the tipping is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenTippingNotPaused() {
        _requireTippingNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the minting is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenMintingPaused() {
        _requireMintingPaused();
        _;
    }
    /**
     * @dev Modifier to make a function callable only when the renewal is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenRenewalPaused() {
        _requireRenewalPaused();
        _;
    }
    /**
     * @dev Modifier to make a function callable only when the tipping is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenTippingPaused() {
        _requireTippingPaused();
        _;
    }

    /**
     * @dev Returns true if the mint is paused, and false otherwise.
     */
    function mintingPaused() public view virtual returns (bool) {
        return _mintingPaused;
    }

    /**
     * @dev Returns true if renewal is paused, and false otherwise.
     */
    function renewalPaused() public view virtual returns (bool) {
        return _renewalPaused;
    }

    /**
     * @dev Returns true if renewal is paused, and false otherwise.
     */
    function tippingPaused() public view virtual returns (bool) {
        return _tippingPaused;
    }

    /**
     * @dev Throws if minting is paused.
     */
    function _requireMintingNotPaused() internal view virtual {
        require(!mintingPaused(), "Pausable: minting paused");
    }

    /**
     * @dev Throws if renewal is paused.
     */
    function _requireRenewalNotPaused() internal view virtual {
        require(!renewalPaused(), "Pausable: renewal paused");
    }

    /**
     * @dev Throws if tipping is paused.
     */
    function _requireTippingNotPaused() internal view virtual {
        require(!tippingPaused(), "Pausable: tipping paused");
    }

    /**
     * @dev Throws if minting is not paused.
     */
    function _requireMintingPaused() internal view virtual {
        require(mintingPaused(), "Pausable: minting not paused");
    }

    /**
     * @dev Throws if renewal is not paused.
     */
    function _requireRenewalPaused() internal view virtual {
        require(renewalPaused(), "Pausable: renewal not paused");
    }
    /**
     * @dev Throws if the contract is not paused.
     */
    function _requireTippingPaused() internal view virtual {
        require(tippingPaused(), "Pausable: tipping not paused");
    }

    /**
     * @dev Triggers stopped minting state.
     *
     * Requirements:
     *
     * - The minting must not be paused.
     */
    function _pauseMinting() internal virtual whenMintingNotPaused {
        _mintingPaused = true;
        emit MintingPaused(_msgSender());
    }
    /**
     * @dev Triggers stopped minting state.
     *
     * Requirements:
     *
     * - The renewal must not be paused.
     */
    function _pauseRenewal() internal virtual whenRenewalNotPaused {
        _renewalPaused = true;
        emit RenewalPaused(_msgSender());
    }
    /**
     * @dev Triggers stopped minting state.
     *
     * Requirements:
     *
     * - The tipping must not be paused.
     */
    function _pauseTipping() internal virtual whenTippingNotPaused {
        _tippingPaused = true;
        emit TippingPaused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The minting must be paused.
     */
    function _unpauseMinting() internal virtual whenMintingPaused {
        _mintingPaused = false;
        emit MintingUnpaused(_msgSender());
    }
    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The renewal must be paused.
     */
    function _unpauseRenewal() internal virtual whenRenewalPaused {
        _renewalPaused = false;
        emit RenewalUnpaused(_msgSender());
    }
    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The tipping must be paused.
     */
    function _unpauseTipping() internal virtual whenTippingPaused {
        _tippingPaused = false;
        emit TippingUnpaused(_msgSender());
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

