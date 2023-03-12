// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Blockaware.sol";

abstract contract Blockdetermined is Blockaware {

  uint internal _block;

  function _currentBlock() internal view virtual override(Blockaware) returns (uint) {

    return _block;
  }

  function setCurrentBlock(uint _newBlock) public {
    _block = _newBlock;
  }

  function getCurrentBlock() public view returns (uint) {
    return _currentBlock();
  }

}
