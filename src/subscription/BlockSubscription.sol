// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DefaultSubscription} from "./Subscription.sol";

/**
 * @title Block number Subscription
 * @notice A Subscription implementation that uses the block number as its time unit
 */
contract BlockSubscription is DefaultSubscription {
    constructor(address handleContract) DefaultSubscription(handleContract) {}

    function _now() internal view override returns (uint64) {
        return uint64(block.number);
    }
}