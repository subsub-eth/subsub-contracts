// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/subscription/Subscription.sol";

contract TestSubscription is DefaultSubscription {
    uint256 private __now;

    constructor(address handleContract) DefaultSubscription(handleContract) {}

    function _now() internal view override returns (uint256) {
        return __now;
    }

    function setNow(uint256 newNow) public {
        __now = newNow;
    }

    function getSubData(uint256 tokenId) public view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        SubData memory s = _getSubData(tokenId);
        return (s.mintedAt, s.totalDeposited, s.lastDepositAt, s.currentDeposit, s.lockedAmount, s.multiplier);
    }
}
