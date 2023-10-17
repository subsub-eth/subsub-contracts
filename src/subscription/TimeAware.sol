// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract TimeAware {

    function _now() internal view virtual returns (uint256);

}
