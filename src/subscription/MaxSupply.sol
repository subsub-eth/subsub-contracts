// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract HasMaxSupply {

    function _maxSupply() internal virtual view returns (uint256);
}

abstract contract MaxSupply is Initializable, HasMaxSupply {

    uint256 private __maxSupply;

    function __MaxSupply_init(uint256 maxSupply) internal onlyInitializing {
        __MaxSupply_init_unchained(maxSupply);
    }

    function __MaxSupply_init_unchained(uint256 maxSupply) internal onlyInitializing {
      __maxSupply = maxSupply;
    }


    function _maxSupply() internal override view returns (uint256) {
      return __maxSupply;
    }

    // TODO _gap
}

