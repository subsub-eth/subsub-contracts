// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/subscription/Epochs.sol";

contract TestEpochs is Epochs {
    constructor(uint256 epochSize) initializer {
        __Epochs_init(epochSize);
    }

    function _now() internal view override returns (uint256) {
        return block.number;
    }

    function currentEpoch() external view virtual returns (uint256) {
        return _currentEpoch();
    }

    function claimed() external view virtual returns (uint256) {
        return _claimed();
    }

    function addNewSub(uint256 amount, uint256 shares, uint256 rate) external {
        _addNewSubscriptionToEpochs(amount, shares, rate);
    }

    function claim(uint256 rate) external returns (uint256) {
        return _handleEpochsClaim(rate);
    }
}

contract EpochsTest is Test {
    TestEpochs private e;

    uint256 private epochSize;

    function setUp() public {
        epochSize = 100;

        e = new TestEpochs(epochSize);
    }

    function testClaimed(uint16 jump) public {
        uint256 rate = 10;
        uint256 shares = 100;
        uint256 deposit = 100_000_000;
        e.addNewSub(deposit, shares, rate);

        vm.roll(block.number + 2 * epochSize);

        uint256 claimed = e.claim(rate);
        assertEq(claimed, e.claimed(), "claimed amount stored in contract");

        vm.roll(block.number + jump);

        claimed += e.claim(rate);
        assertEq(claimed, e.claimed(), "another claim accounted for");
    }

    function testClaimed_atInit() public {
        assertEq(0, e.claimed(), "initialized at 0");
    }
}
