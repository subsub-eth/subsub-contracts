// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Epochs.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

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

    function scanEpochs(uint256 rate, uint64 upToEpoch)
        external
        view
        virtual
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        return _scanEpochs(rate, upToEpoch);
    }

    function addNewSub(uint256 amount, uint256 shares, uint256 rate) external {
        _addToEpochs(amount, shares, rate);
    }

    function moveSubscriptionInEpochs(
        uint256 oldDepositedAt,
        uint256 oldDeposit,
        uint256 newDepositedAt,
        uint256 newDeposit,
        uint256 shares,
        uint256 rate
    ) external {
        _moveInEpochs(oldDepositedAt, oldDeposit, newDepositedAt, newDeposit, shares, rate);
    }

    function claim(uint256 rate) external returns (uint256) {
        return _claimEpochs(rate);
    }
}

contract EpochsTest is Test {
    using Math for uint256;

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

        (uint256 claimable,,) = e.scanEpochs(rate, e.currentEpoch());
        uint256 claimed = e.claim(rate);
        assertEq(claimable, claimed, "1st claim: claimed amount equal to claimable");
        assertEq(claimed, e.claimed(), "1st claim: claimed amount stored in contract");

        vm.roll(block.number + jump);

        (claimable,,) = e.scanEpochs(rate, e.currentEpoch());
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
        // only valid for 1 block
        e.addNewSub(rate, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active even after expiration in current epoch");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_multiplier(uint16 shares) public {
        uint256 rate = 10;
        uint256 amount = 100_000;
        shares = uint16(bound(shares, 100, 10_000));
        e.addNewSub(amount, shares, rate);
        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(((amount * 100) / (rate * shares)) + 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        vm.roll(((amount * 100) / (rate * shares)) + epochSize + 1);
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
        vm.roll(firstExpire + 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        // add second sub
        shares = 125;
        amount = 50_000;
        e.addNewSub(amount, shares, rate);
        assertEq(e.activeSubShares(), shares + 100, "both subs are active");

        vm.roll(firstExpire + epochSize + 1);
        assertEq(e.activeSubShares(), shares, "only second sub active");

        vm.roll(firstExpire + (((amount * 100) / (rate * shares))) + 1);
        assertEq(e.activeSubShares(), shares, "second sub about to expire");

        vm.roll(firstExpire + (((amount * 100) / (rate * shares)) + epochSize) + 1);
        assertEq(e.activeSubShares(), 0, "2nd sub expired");
    }

    function testActiveSubShares_2subParallel() public {
        uint256 rate = 10;
        uint256 shares = 100;
        uint256 amount = 100_000;
        uint256 shares2 = 222;
        uint256 amount2 = 2_200_000;

        e.addNewSub(amount, shares, rate);
        e.addNewSub(amount2, shares2, rate);
        assertEq(e.activeSubShares(), shares + shares2, "both new subs active");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares + shares2, "first epoch: both subs active");

        uint256 firstExpire = ((amount * 100) / (rate * shares));
        vm.roll(firstExpire + 1);
        assertEq(e.activeSubShares(), shares + shares2, "first sub about to expire");

        vm.roll(firstExpire + epochSize + 1);
        assertEq(e.activeSubShares(), shares2, "first sub expired");

        uint256 secondExpire = ((amount2 * 100) / (rate * shares2));
        vm.roll(secondExpire + 1);
        assertEq(e.activeSubShares(), shares2, "second sub about to expire");

        vm.roll(secondExpire + epochSize + 1);
        assertEq(e.activeSubShares(), 0, "second sub expired");
    }

    function testActiveSubShares_extendExpiringSubscription(uint16 shares) public {
        shares = uint16(bound(shares, 100, 10_000));

        uint256 rate = 10;
        uint256 initDeposit = (100_000 * uint256(shares)) / 100;
        uint256 initDepositAt = 10;
        vm.roll(initDepositAt);

        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.roll(initDepositAt + epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(initDepositAt + ((initDeposit * 100) / (rate * shares)));
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        uint256 nextDepositAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 nextDeposit = (200_000 * uint256(shares)) / 100;
        e.moveSubscriptionInEpochs(initDepositAt, initDeposit, nextDepositAt, nextDeposit, shares, rate);

        vm.roll(initDepositAt + ((initDeposit * 100) / (rate * shares)) + epochSize);
        assertEq(e.activeSubShares(), shares, "sub extended");

        vm.roll(nextDepositAt + ((nextDeposit * 100) / (rate * shares)));
        assertEq(e.activeSubShares(), shares, "end of sub extended");

        vm.roll(nextDepositAt + ((nextDeposit * 100) / (rate * shares)) + epochSize);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    // overlapping, extending a very active subscription
    function testActiveSubShares_extendSubscription(uint16 shares, uint256 nextDepositAt) public {
        shares = uint16(bound(shares, 100, 10_000));

        uint256 rate = 10;
        uint256 initDeposit = (100_000 * uint256(shares)) / 100;
        uint256 initDepositAt = 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        nextDepositAt = bound(nextDepositAt, initDepositAt, initExpiresAt);
        uint256 usedFunds = ((nextDepositAt - initDepositAt) * (rate * shares)) / 100;
        uint256 nextDeposit = ((200_000 * uint256(shares)) / 100) + initDeposit - usedFunds;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(nextDepositAt);
        e.moveSubscriptionInEpochs(initDepositAt, initDeposit, nextDepositAt, nextDeposit, shares, rate);

        vm.roll(initDepositAt + ((initDeposit * 100) / (rate * shares)) + epochSize);
        assertEq(e.activeSubShares(), shares, "sub extended");

        vm.roll(initDepositAt + (300_000 / rate)); // normalized
        assertEq(e.activeSubShares(), shares, "end of sub extended");

        vm.roll(initDepositAt + (300_000 / rate) + epochSize); // normalized
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testMoveSubscription_extendExpiredSubscription(uint16 shares, uint256 nextDepositAt) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));
        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        nextDepositAt = bound(nextDepositAt, initExpiresAt + 1, initExpiresAt * 100);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(nextDepositAt + epochSize); // next epoch after expiry
        assertEq(e.activeSubShares(), 0, "initial sub expired");

        vm.expectRevert();
        // cannot extend an expired sub
        e.moveSubscriptionInEpochs(initDepositAt, initDeposit, nextDepositAt, 1, shares, rate);
    }

    function testProcessEpochs_noSubs() public view {
        uint256 rate = 10;

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 25);
        assertEq(amount, 0, "no funds claimable");
        assertEq(starting, 0, "sub is starting");
        assertEq(expiring, 0, "sub not expiring");
    }

    function testProcessEpochs(uint16 shares) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 0);
        assertEq(amount, 0, "init: no funds claimable");
        assertEq(starting, 0, "init: sub is starting");
        assertEq(expiring, 0, "init: sub not expiring");

        // check each subsequent epoch
        for (uint64 i = 1; i <= (uint64(initExpiresAt) / epochSize); i++) {
            (amount, starting, expiring) = e.scanEpochs(rate, i);
            assertEq(
                amount, ((rate * shares) * ((epochSize * i) - initDepositAt)) / 100, "epoch i: partial funds claimable"
            );
            assertEq(starting, shares, "epoch i: sub is starting");
            assertEq(expiring, 0, "epoch i: sub not expiring");
        }

        (amount, starting, expiring) = e.scanEpochs(rate, (uint64(initExpiresAt) / epochSize) + 1);
        assertEq(amount, initDeposit, "last epoch: all funds claimable");
        assertEq(starting, shares, "last epoch: sub is starting");
        assertEq(expiring, shares, "last epoch: sub is expiring");
    }

    function testProcessEpochs_multiple_totalAmount(uint16 shares1, uint16 shares2) public {
        uint256 rate = 10;
        uint256 deposit1 = 100_000;
        uint256 deposit1At = 10;

        uint256 deposit2 = 200_000;
        uint256 deposit2At = deposit1At + (epochSize * bound(shares2, 1, 10));

        shares1 = uint16(bound(shares1, 100, 10_000));
        shares2 = uint16(bound(shares2, 100, 10_000));

        uint256 deposit1ExpiresAt = deposit1At + ((deposit1 * 100) / (rate * shares1));
        uint256 deposit2ExpiresAt = deposit2At + ((deposit2 * 100) / (rate * shares2));

        vm.roll(deposit1At);
        // initialize sub
        e.addNewSub(deposit1, shares1, rate);

        vm.roll(deposit2At);
        // add 2nd sub
        e.addNewSub(deposit2, shares2, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 0);
        assertEq(amount, 0, "init: no funds claimable");
        assertEq(starting, 0, "init: sub is starting");
        assertEq(expiring, 0, "init: sub not expiring");

        (amount, starting, expiring) =
            e.scanEpochs(rate, (uint64(deposit1ExpiresAt.max(deposit2ExpiresAt)) / epochSize) + 1);
        assertEq(amount, deposit1 + deposit2, "last epoch: all funds claimable");
        assertEq(starting, shares1 + shares2, "last epoch: sub is starting");
        assertEq(expiring, shares1 + shares2, "last epoch: sub is expiring");
    }

    function testClaim(uint16 shares) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        uint256 totalClaimed = 0;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        {
            // claim epoch 0
            vm.roll(initDepositAt + epochSize);

            uint256 amount = e.claim(rate);
            totalClaimed += amount;

            assertEq(amount, (rate * shares * (epochSize - initDepositAt)) / 100, "epoch 0: partial funds claimable");

            assertEq(totalClaimed, e.claimed(), "epoch 0: total claimed");
            assertEq(0, e.lastProcessedEpoch(), "epoch 0: last processed epoch");
        }
        // check each subsequent epoch
        for (uint64 i = 2; i <= (uint64(initExpiresAt) / epochSize); i++) {
            vm.roll(initDepositAt + (i * epochSize));

            uint256 amount = e.claim(rate);
            totalClaimed += amount;
            assertEq(amount, (rate * shares * epochSize) / 100, "epoch i: partial funds claimable");

            assertEq(totalClaimed, e.claimed(), "epoch i: total claimed");
            assertEq(i - 1, e.lastProcessedEpoch(), "epoch i: last processed epoch");
        }

        {
            vm.roll(initExpiresAt + epochSize);

            uint256 amount = e.claim(rate);
            totalClaimed += amount;

            assertEq(totalClaimed, e.claimed(), "last epoch: total claimed");
            assertEq(totalClaimed, initDeposit, "last epoch: total claimable funds");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch: last processed epoch");
        }
    }

    function testClaim_single_total(uint16 shares) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        {
            vm.roll(initExpiresAt + epochSize);

            e.claim(rate);

            assertEq(initDeposit, e.claimed(), "last epoch: total funds claimed");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch: last processed epoch");
        }
    }

    function testClaim_mutliple_total(uint16 shares1, uint16 shares2) public {
        uint256 rate = 10;
        uint256 deposit1 = 100_000;
        uint256 deposit1At = 10;

        uint256 deposit2 = 200_000;
        uint256 deposit2At = deposit1At + (epochSize * bound(shares2, 1, 10));

        shares1 = uint16(bound(shares1, 100, 10_000));
        shares2 = uint16(bound(shares2, 100, 10_000));

        uint256 deposit1ExpiresAt = deposit1At + ((deposit1 * 100) / (rate * shares1));
        uint256 deposit2ExpiresAt = deposit2At + ((deposit2 * 100) / (rate * shares2));

        vm.roll(deposit1At);
        // initialize sub
        e.addNewSub(deposit1, shares1, rate);

        vm.roll(deposit2At);
        // add 2nd sub
        e.addNewSub(deposit2, shares2, rate);

        vm.roll(deposit1ExpiresAt.max(deposit2ExpiresAt) + epochSize);

        e.claim(rate);

        assertEq(deposit1 + deposit2, e.claimed(), "last epoch: total funds claimed");
        assertEq(deposit1ExpiresAt.max(deposit2ExpiresAt) / epochSize, e.lastProcessedEpoch(), "last epoch: last processed epoch");
    }

    function testClaim_epoch0(uint16 shares) public {
        uint256 rate = 10;
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.expectRevert(); // cannot handle claim of epoch 0
        e.claim(rate);
    }

    function testClaim_noSubs() public {
        uint256 rate = 10;
        uint64 epoch = 25;

        vm.roll(epochSize * epoch);

        uint256 amount = e.claim(rate);
        assertEq(0, amount, "no funds claimed");

        assertEq(0, e.claimed(), "total funds 0");
        assertEq(epoch - 1, e.lastProcessedEpoch(), "last processed epoch advanced to previous epoch");
    }
}