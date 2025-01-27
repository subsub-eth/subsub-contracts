// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

interface IHasFlags {
    function flagsEnabled(uint256 flags) external view returns (bool);

    function getFlags() external view returns (uint256);
}

interface FlagEvents {
    event FlagSet(address account, uint256 flag, uint256 newFlags);
}

abstract contract HasFlagSettings is IHasFlags {
    function _setFlags(uint256 flags) internal virtual;

    function _requireDisabled(uint256 flag) internal view virtual;

    function _requireEnabled(uint256 flag) internal view virtual;

    // slither-disable-next-line incorrect-modifier
    modifier whenDisabled(uint256 flags) virtual;

    // slither-disable-next-line incorrect-modifier
    modifier whenEnabled(uint256 flags) virtual;
}

abstract contract FlagSettings is Initializable, ContextUpgradeable, FlagEvents, HasFlagSettings {
    struct FlagStorage {
        uint256 _flags;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.FlagSettings")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant FlagStorageLocation = 0xc5c3d7bab6cceabb922a9285107a3807dc3d1fd42d4176d3391dfe1aba2acc00;

    function _getFlagStorage() private pure returns (FlagStorage storage $) {
        // solhint-disable no-inline-assembly
        assembly {
            $.slot := FlagStorageLocation
        }
        // solhint-enable no-inline-assembly
    }

    // slither-disable-start dead-code
    function __FlagSettings_init() internal onlyInitializing {
        __FlagSettings_init_unchained();
    }
    // slither-disable-end dead-code

    function __FlagSettings_init_unchained() internal onlyInitializing {
        FlagStorage storage $ = _getFlagStorage();
        $._flags = 0;
    }

    function _requireDisabled(uint256 flag) internal view virtual override {
        require(!flagsEnabled(flag), "Flag: setting enabled");
    }

    // slither-disable-start dead-code
    function _requireEnabled(uint256 flag) internal view virtual override {
        require(flagsEnabled(flag), "Flag: setting disabled");
    }
    // slither-disable-end dead-code

    modifier whenDisabled(uint256 flags) virtual override {
        _requireDisabled(flags);
        _;
    }

    modifier whenEnabled(uint256 flags) virtual override {
        _requireEnabled(flags);
        _;
    }

    function _setFlags(uint256 flags) internal override {
        FlagStorage storage $ = _getFlagStorage();
        uint256 oldFlags = $._flags;
        $._flags = flags;
        emit FlagSet(_msgSender(), flags, oldFlags);
    }

    function flagsEnabled(uint256 flags) public view override returns (bool) {
        FlagStorage storage $ = _getFlagStorage();
        return ($._flags & flags) == flags;
    }

    function getFlags() public view override returns (uint256) {
        FlagStorage storage $ = _getFlagStorage();
        return $._flags;
    }
}
