// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/subscription/Subscription.sol";

contract TestSubscription is Subscription {
    uint256 private __now;

    function _now() internal override view returns (uint256) {
      return __now;
    }

    function setNow(uint256 newNow) public {
      __now = newNow;
    }
}
