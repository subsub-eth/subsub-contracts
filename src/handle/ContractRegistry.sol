// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract HasContractRegistry {
    function _addToRegistry(address addr, bool isManaged) internal virtual returns (bool);

    function _isManaged(address addr) internal view virtual returns (bool);
}

abstract contract ContractRegistry is Initializable, HasContractRegistry {
    struct ContractRegistryStorage {
        // 00 00 00 00
        //           ^ is registered
        //          ^ is managed
        mapping(address => uint8) _registry;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.handle.ContractRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ContractRegistryStorageLocation =
        0x7101d9eaf2c399621b29010cbd8463395477ce71e1068af39595d8af2086ff00;

    function _getContractRegistryStorage() private pure returns (ContractRegistryStorage storage $) {
        assembly {
            $.slot := ContractRegistryStorageLocation
        }
    }

    function __ContractRegistry_init() internal onlyInitializing {}

    function __ContractRegistry_init_unchained() internal onlyInitializing {}

    function _addToRegistry(address addr, bool isManaged) internal override returns (bool) {
        ContractRegistryStorage storage $ = _getContractRegistryStorage();

        if ($._registry[addr] > 0) {
            return false;
        } // else
        // only change if value is not already set
        $._registry[addr] = 1 + (isManaged ? 2 : 0);
        return true;
    }

    function _isManaged(address addr) internal view override returns (bool) {
        ContractRegistryStorage storage $ = _getContractRegistryStorage();
        return $._registry[addr] == 3;
    }
}
