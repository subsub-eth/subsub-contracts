// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @notice provides an overridable function to access the current block. Useful 
 * for testing purposes.
 */
abstract contract Blockaware {

  /**
    * @notice Returns the current block number
    */
  function _currentBlock() internal view virtual returns (uint) {

    return block.number;
  }
}
