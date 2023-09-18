// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Subscription} from "./Subscription.sol";

contract TimestampSubscription is Subscription {

    function _now() internal override view returns (uint256) {
      return block.timestamp;
    }
}
