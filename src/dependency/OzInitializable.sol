// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev internal interface exposing OZ {Initializable} methods without binding
 * to the implementation. The actually implementation needs to be overriden
 * later.
 */
abstract contract OzInitializable {
    function _checkInitializing() internal view virtual;
}
