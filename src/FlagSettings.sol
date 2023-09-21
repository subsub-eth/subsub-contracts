// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract FlagSettings is Initializable, ContextUpgradeable {
    event FlagSet(address account, uint8 flag, uint8 newFlags);
    event FlagUnset(address account, uint8 flag, uint8 newFlags);

    uint8 private _flags;

    function __FlagSettings_init() internal onlyInitializing {
        __FlagSettings_init_unchained();
    }

    function __FlagSettings_init_unchained() internal onlyInitializing {
        _flags = 0;
    }

    function _setFlags(uint8 flags) internal virtual {
        _flags = _flags | flags;
        emit FlagSet(_msgSender(), flags, _flags);
    }

    function _unsetFlags(uint8 flags) internal virtual {
        _flags = _flags ^ flags;
        emit FlagUnset(_msgSender(), flags, _flags);
    }

    function flagsEnabled(uint8 flags) public view virtual returns (bool) {
        return (_flags & flags) == flags;
    }

    function getFlags() public view virtual returns (uint8) {
        return _flags;
    }

    function _requireDisabled(uint8 flag) internal view virtual {
        require(!flagsEnabled(flag), "Flag: settings enabled");
    }

    function _requireEnabled(uint8 flag) internal view virtual {
        require(flagsEnabled(flag), "Flag: settings disabled");
    }

    modifier whenDisabled(uint8 flags) {
        _requireDisabled(flags);
        _;
    }

    modifier whenEnabled(uint8 flags) {
        _requireEnabled(flags);
        _;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
