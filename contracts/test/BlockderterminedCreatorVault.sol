// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../CreatorVault.sol";
import "../util/Blockdetermined.sol";

/**
  * @title CreatorVault that allows for artifical change of the block number
  * for deterministic testing
  */
contract BlockdeterminedCreatorVault is CreatorVault, Blockdetermined {

  constructor(address _creator, address _token) CreatorVault(_creator, _token) {

  }

  // this sucks
  function _currentBlock() internal view virtual override(Blockaware, Blockdetermined) returns (uint) {
    return _block;
  }

}
