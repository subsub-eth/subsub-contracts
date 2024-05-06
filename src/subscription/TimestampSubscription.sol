// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DefaultSubscription} from "./Subscription.sol";

contract TimestampSubscription is DefaultSubscription {
    constructor(address handleContract) DefaultSubscription(handleContract) {}

    function _now() internal view override returns (uint64) {
        return uint64(block.timestamp);
    }
}