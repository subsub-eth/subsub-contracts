// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev internal interface exposing OZ {Context} methods without binding to
 * the implementation. The actually implementation needs to be overriden later.
 */
abstract contract OzContext {
    function _msgSender() internal view virtual returns (address);
}
