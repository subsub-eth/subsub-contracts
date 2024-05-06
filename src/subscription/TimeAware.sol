// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title A time aware mixin
 * @notice returns some sort of internal time unit that is increasing
 * @dev Valid time units might be the unix epoch or the block time
 */
abstract contract TimeAware {

    /**
     * @notice the current time unit
     * @dev the current time is represented as an i64. Higher values seem unreasonable
     * @return the current time unit
     */
    function _now() internal view virtual returns (uint64);

}