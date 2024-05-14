// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Epochs.sol";

contract TestEpochs is Epochs {
    constructor(uint64 epochSize_) initializer {
        __Epochs_init(epochSize_);
    }

    function _now() internal view override returns (uint64) {
        return uint64(block.number);
    }

    function epochSize() external view virtual returns (uint64) {
        return _epochSize();
    }

    function currentEpoch() external view virtual returns (uint64) {
        return _currentEpoch();
    }

    function lastProcessedEpoch() external view virtual returns (uint64) {
        return _lastProcessedEpoch();
    }

    function activeSubShares() external view virtual returns (uint256) {
        return _activeSubShares();
    }

    function claimed() external view virtual returns (uint256) {
        return _claimed();
    }

    function processEpochs(uint256 rate, uint64 upToEpoch)
        external
        view
        virtual
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        return _processEpochs(rate, upToEpoch);
    }

    function addNewSub(uint256 amount, uint256 shares, uint256 rate) external {
        _addNewSubscriptionToEpochs(amount, shares, rate);
    }

    function moveSubscriptionInEpochs(
        uint256 oldDepositedAt,
        uint256 oldDeposit,
        uint256 newDepositedAt,
        uint256 newDeposit,
        uint256 shares,
        uint256 rate
    ) external {
        _moveSubscriptionInEpochs(oldDepositedAt, oldDeposit, newDepositedAt, newDeposit, shares, rate);
    }

    function claim(uint256 rate) external returns (uint256) {
        return _handleEpochsClaim(rate);
    }
}

contract EpochsTest is Test {
    TestEpochs private e;

    uint64 private epochSize;

    function setUp() public {
        epochSize = 100;

        e = new TestEpochs(epochSize);
    }

    function test_claimSingleSub(uint16 jump) public {
        uint256 rate = 10;
        uint256 shares = 100;
        uint256 deposit = 100_000_000;
        e.addNewSub(deposit, shares, rate);

        vm.roll(block.number + 2 * epochSize);

        (uint256 claimable,,) = e.processEpochs(rate, e.currentEpoch());
        uint256 claimed = e.claim(rate);
        assertEq(claimable, claimed, "1st claim: claimed amount equal to claimable");
        assertEq(claimed, e.claimed(), "1st claim: claimed amount stored in contract");

        vm.roll(block.number + jump);

        (claimable,,) = e.processEpochs(rate, e.currentEpoch());
        uint256 claimed2 = e.claim(rate);
        assertEq(claimable, claimed2, "2nd claim: claimed amount equal to claimable");
        assertEq(claimed + claimed2, e.claimed(), "2nd claim: claimed amount is updated");
    }

    function testClaimed_init() public view {
        assertEq(0, e.claimed(), "initialized at 0");
    }

    function testLastProcessedEpoch_init0() public view {
        assertEq(0, e.lastProcessedEpoch(), "initialized at 0");
    }

    function testLastProcessedEpoch_init(uint64 time) public {
        time = uint64(bound(time, epochSize + 1, type(uint64).max));
        vm.roll(time);

        e = new TestEpochs(epochSize);
        assertEq(
            (block.number / epochSize) - 1, e.lastProcessedEpoch(), "last processed epoch initialized to last epoch"
        );
    }

    function testActiveSubShares_new() public {
        uint256 rate = 10;
        uint256 shares = 100;
        e.addNewSub(100_000, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active");
    }

    function testActiveSubShares_expiredImmediately() public {
        uint256 rate = 10;
        uint256 shares = 100;
        e.addNewSub(10, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active even after expiration in current epoch");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_nextEpoch(uint16 shares) public {
        uint256 rate = 10;
        shares = uint16(bound(shares, 100, 10_000));
        e.addNewSub(100_000, shares, rate);
        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(100 * epochSize);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        vm.roll(epochSize + 100 * epochSize);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_multiplier(uint16 multiplier, uint256 rate, uint256 amount) public {
        rate = bound(rate, 1, type(uint128).max);
        amount = bound(amount, rate * epochSize, 123 * rate);

        uint256 shares = bound(multiplier, 100, 10_000);

        e.addNewSub(amount, shares, rate);
        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll((amount / (rate * epochSize)) * epochSize);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        vm.roll(epochSize + (amount / (rate * epochSize)) * epochSize);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_2subSequential() public {
        uint256 rate = 10;
        uint256 shares = 100;
        uint256 amount = 100_000;
        e.addNewSub(amount, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active even after expiration in current epoch");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        uint256 firstExpire = (amount / (rate * epochSize)) * epochSize;
        vm.roll(firstExpire);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        // add second sub
        rate = 20;
        shares = 125;
        amount = 50_000;
        e.addNewSub(amount, shares, rate);
        assertEq(e.activeSubShares(), shares + 100, "both subs are active");

        vm.roll(firstExpire + epochSize);
        assertEq(e.activeSubShares(), shares, "only second sub active");

        vm.roll(firstExpire + ((amount / (rate * epochSize)) * epochSize) + epochSize);
        assertEq(e.activeSubShares(), 0, "2nd sub expired");
    }

    function testActiveSubShares_2subParallel() public {
        uint256 rate = 10;
        uint256 shares = 100;
        uint256 amount = 100_000;
        uint256 rate2 = 15;
        uint256 shares2 = 222;
        uint256 amount2 = 220_000;

        e.addNewSub(amount, shares, rate);
        e.addNewSub(amount2, shares2, rate2);
        assertEq(e.activeSubShares(), shares + shares2, "both new subs active");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares + shares2, "first epoch: both subs active");

        uint256 firstExpire = (amount / (rate * epochSize)) * epochSize;
        vm.roll(firstExpire + epochSize);
        assertEq(e.activeSubShares(), shares2, "first sub expired");

        uint256 secondExpire = (amount2 / (rate2 * epochSize)) * epochSize;
        vm.roll(secondExpire + epochSize);
        assertEq(e.activeSubShares(), 0, "second sub expired");
    }

    function testActiveSubShares_extendExpiringSubscription(uint16 shares) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;
        vm.roll(initDepositAt);
        shares = uint16(bound(shares, 100, 10_000));

        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.roll(initDepositAt + epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(initDepositAt + (initDeposit / rate) );
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        uint256 nextDepositAt = initDepositAt + (initDeposit / rate);
        uint256 nextDeposit = 200_000;
        e.moveSubscriptionInEpochs(initDepositAt, initDeposit, nextDepositAt, nextDeposit, shares, rate);

        vm.roll(initDepositAt + (initDeposit / rate) + epochSize);
        assertEq(e.activeSubShares(), shares, "sub extended");

        vm.roll(nextDepositAt + (nextDeposit / rate));
        assertEq(e.activeSubShares(), shares, "end of sub extended");

        vm.roll(nextDepositAt + (nextDeposit / rate) + epochSize);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_extendSubscription(uint16 shares, uint256 nextDepositAt) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));
        uint256 initExpiresAt = initDepositAt + (initDeposit / rate);
        nextDepositAt = bound(nextDepositAt, initDepositAt, initExpiresAt);
        uint256 usedFunds = (nextDepositAt - initDepositAt) * rate;
        uint256 nextDeposit = 200_000 + initDeposit - usedFunds;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(nextDepositAt);
        e.moveSubscriptionInEpochs(initDepositAt, initDeposit, nextDepositAt, nextDeposit, shares, rate);

        vm.roll(initDepositAt + (initDeposit / rate) + epochSize);
        assertEq(e.activeSubShares(), shares, "sub extended");

        vm.roll(initDepositAt + (300_000 / rate));
        assertEq(e.activeSubShares(), shares, "end of sub extended");

        vm.roll(initDepositAt + (300_000 / rate) + epochSize);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testMoveSubscription_extendExpiredSubscription(uint16 shares, uint256 nextDepositAt) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));
        uint256 initExpiresAt = initDepositAt + (initDeposit / rate);
        nextDepositAt = bound(nextDepositAt, initExpiresAt + 1, type(uint64).max);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(nextDepositAt);
        vm.expectRevert();
        e.moveSubscriptionInEpochs(initDepositAt, initDeposit, nextDepositAt, 1, shares, rate);
    }

    function testProcessEpochs(uint16 shares) public {
        uint256 rate = 10;
        uint256 initDeposit = 10_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));
        uint256 initExpiresAt = initDepositAt + (initDeposit / rate);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        (uint256 amount, uint256 starting, uint256 expiring) = e.processEpochs(rate, 0);
        assertEq(amount, 0, "init: no funds claimable");
        assertEq(starting, 0, "init: sub is starting");
        assertEq(expiring, 0, "init: sub not expiring");

        (amount, starting, expiring) = e.processEpochs(rate, 1);
        assertEq(amount, rate * (epochSize - initDepositAt), "epoch 0: partial funds claimable");
        assertEq(starting, shares, "epoch 0: sub is starting");
        assertEq(expiring, 0, "epoch 0: sub not expiring");

        (amount, starting, expiring) = e.processEpochs(rate, (uint64(initExpiresAt) / epochSize) + 1);
        assertEq(amount, initDeposit, "last epoch: all funds claimable");
        assertEq(starting, shares, "last epoch: sub is starting");
        assertEq(expiring, shares, "last epoch: sub is expiring");
    }

    // TODO claimable
    // TODO claim
}