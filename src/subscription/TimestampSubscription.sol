// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DefaultSubscription} from "./Subscription.sol";

contract TimestampSubscription is DefaultSubscription {

    function _now() internal override view returns (uint256) {
      return block.timestamp;
    }
}
