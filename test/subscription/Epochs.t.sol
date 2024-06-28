// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Epochs.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract TestEpochs is Epochs {
    constructor(uint64 epochSize_) initializer {
        __Epochs_init(epochSize_);
    }

    function _now() internal view override returns (uint256) {
        return block.number;
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

    function extendInEpochs(uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        external
    {
        _extendInEpochs(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function reduceInEpochs(uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        external
    {
        _reduceInEpochs(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function claim(uint256 rate) external returns (uint256) {
        return _claimEpochs(rate);
    }
}

contract EpochsTest is Test {
    using Math for uint256;

    TestEpochs private e;

    uint64 private epochSize;
    uint256 rate;

    function setUp() public {
        epochSize = 100;
        rate = 10;

        e = new TestEpochs(epochSize);
    }

    function oneTimeUnit(uint256 _rate, uint256 _shares) private pure returns (uint256) {
        return ((_rate * _shares) / 100) + 1;
    }

    function test_claimSingleSub(uint16 jump) public {
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
        uint256 shares = 100;
        e.addNewSub(100_000, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active");
    }

    function testActiveSubShares_expiredImmediately() public {
        uint256 shares = 100;
        // only valid for 1 block
        e.addNewSub(rate, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active even after expiration in current epoch");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_multiplier(uint16 shares) public {
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

    function testActiveSubShares_extendSubscription_initNotOneEpoch(
        uint16 shares,
        uint256 initDeposit,
        uint256 newDeposit
    ) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, epochSize * oneTimeUnit(rate, shares), 1_000_000);
        newDeposit = bound(newDeposit, initDeposit + oneTimeUnit(rate, shares), initDeposit * 10);

        uint64 initDepositAt = epochSize / 10;
        uint64 initExpiresAt = initDepositAt + uint64((initDeposit * 100) / (rate * shares));

        assertNotEq(initDepositAt / epochSize, initExpiresAt / epochSize, "init sub not in 1 epoch");
        vm.roll(initDepositAt);

        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.roll(initDepositAt + epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(initExpiresAt - 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        //////////
        //////////
        //////////
        uint64 newExpiresAt = initDepositAt + uint64((newDeposit * 100) / (rate * shares));
        assertGt(newExpiresAt, initExpiresAt, "sanity: longer expiration");

        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        if (initExpiresAt / epochSize != newExpiresAt / epochSize) {
            vm.roll(initExpiresAt + epochSize);
            assertEq(e.activeSubShares(), shares, "init sub extended");
        }

        vm.roll(newExpiresAt);
        assertEq(e.activeSubShares(), shares, "end of extended sub");

        vm.roll(newExpiresAt + epochSize);
        assertEq(e.activeSubShares(), 0, "extended sub expired");
    }

    // initial sub starts and expires within a single epoch
    function testActiveSubShares_extendSubscription_initOneEpoch(uint16 shares, uint256 newDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        uint256 initDeposit = (epochSize / 6) * oneTimeUnit(rate, shares);
        newDeposit = bound(newDeposit, initDeposit + (rate * shares), initDeposit * 10);

        uint64 initDepositAt = epochSize / 10;
        uint64 initExpiresAt = initDepositAt + uint64((initDeposit * 100) / (rate * shares));

        assertEq(initDepositAt / epochSize, initExpiresAt / epochSize, "init sub not in 1 epoch");
        vm.roll(initDepositAt);

        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.roll(initDepositAt);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(initExpiresAt - 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        //////////
        //////////
        //////////
        uint64 newExpiresAt = initDepositAt + uint64((newDeposit * 100) / (rate * shares));
        assertGt(newExpiresAt, initExpiresAt, "sanity: longer expiration");

        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        vm.roll(initExpiresAt + epochSize);
        assertEq(e.activeSubShares(), shares, "init sub extended");

        vm.roll(newExpiresAt);
        assertEq(e.activeSubShares(), shares, "end of extended sub");

        vm.roll(newExpiresAt + epochSize);
        assertEq(e.activeSubShares(), 0, "extended sub expired");
    }

    function testExtendSubscription_extendExpiredSubscription(uint16 shares, uint256 nextDepositAt) public {
        uint256 initDeposit = 100_000;
        uint64 initDepositAt = epochSize / 10;

        shares = uint16(bound(shares, 100, 10_000));
        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        nextDepositAt = bound(nextDepositAt, initExpiresAt + 1, initExpiresAt * 100);
        //
        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(nextDepositAt + epochSize); // next epoch after expiry
        assertEq(e.activeSubShares(), 0, "initial sub expired");

        vm.expectRevert();
        // cannot extend an expired sub
        e.extendInEpochs(initDepositAt, initDeposit, 1, shares, rate);
    }

    function testProcessEpochs_noSubs() public view {
        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 25);
        assertEq(amount, 0, "no funds claimable");
        assertEq(starting, 0, "sub is starting");
        assertEq(expiring, 0, "sub not expiring");
    }

    function testAdd0AmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        e.addNewSub(0, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, 0, "no funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub all expiring");
    }

    function testAdd1AmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        e.addNewSub(1, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, 1, "all funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub expiring");
    }

    function testAdd1TimeUnitAmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        uint256 deposit = (rate * shares) / 100; // 1 time unit
        e.addNewSub(deposit, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, deposit, "all funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub expiring");
    }

    function testAdd1EpochAmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        uint256 deposit = (rate * epochSize * shares) / 100; // 1 epoch size
        e.addNewSub(deposit, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, (rate * (epochSize - 10) * shares) / 100, "e0: partial funds claimable");
        assertEq(starting, shares, "e0: sub is starting");
        assertEq(expiring, 0, "e0: sub expiring");

        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, deposit, "e1: all funds claimable");
        assertEq(starting, shares, "e1: sub is starting");
        assertEq(expiring, shares, "e1: sub expiring");
    }

    function testAddSub(uint16 shares, uint256 deposit) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));
        deposit = bound(deposit, 0, 1_000_000);

        e.addNewSub(deposit, shares, rate);

        uint64 maxEpoch = (1_000_000 / 10) / epochSize;

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, maxEpoch + 1);
        assertEq(amount, deposit, "all funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub expiring");
    }

    function testProcessEpochs(uint16 shares) public {
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = epochSize / 10;

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

    function testProcessEpochs_extendOneEpochSubByOneEpoch(uint16 shares, uint256 initDeposit, uint256 newDeposit)
        public
    {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, epochSize * oneTimeUnit(rate, shares), 1_000_000); // at least 1 epoch
        newDeposit = bound(
            newDeposit,
            initDeposit + (epochSize * oneTimeUnit(rate, shares)),
            initDeposit + (epochSize * oneTimeUnit(rate, shares) * 10)
        ); // add at least another epoch
        uint64 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 newDepositAt = bound(newDeposit, initDepositAt, initExpiresAt - 1);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, uint64(initExpiresAt / epochSize) + 1);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // sub expiration was moved
        (amount, starting, expiring) = e.scanEpochs(rate, uint64(initExpiresAt / epochSize) + 1);
        assertGt(amount, initDeposit, "sub ext: initial funds and new partial deposit claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, 0, "sub exp: sub still active");

        // extended sub expired
        (amount, starting, expiring) =
            e.scanEpochs(rate, uint64((initDepositAt + (newDeposit * 100) / (rate * shares)) / epochSize) + 1);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    // generic extension
    function testProcessEpochs_extendEpoch(uint16 shares, uint256 initDeposit, uint256 newDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, oneTimeUnit(rate, shares), 1_000_000); // at least 1 time unit
        newDeposit = bound(newDeposit, initDeposit + 1, initDeposit + (((epochSize * rate * shares) * 10) / 100)); // at least 1 gwei
        uint64 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = bound(newDeposit, initDepositAt, initExpiresAt - 1);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, uint64(initExpiresAt / epochSize) + 1);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        if ((initExpiresAt / epochSize) != (newExpiresAt / epochSize)) {
            // sub expiration was moved to a new epoch
            (amount, starting, expiring) = e.scanEpochs(rate, uint64(initExpiresAt / epochSize) + 1);
            assertGt(amount, initDeposit, "sub ext: initial funds and new partial deposit claimable");
            assertEq(starting, shares, "sub exp: sub started");
            assertEq(expiring, 0, "sub exp: sub still active");
        }

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, uint64(newExpiresAt / epochSize) + 1);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendMultiEpoch_alreadyExpired() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize; // 1 epoch
        uint256 newDeposit = initDeposit + rate;
        uint64 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(initExpiresAt);
        vm.expectRevert();
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testExtendEpoch_extendMultiEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize; // 1 epoch
        uint256 newDeposit = initDeposit + rate;
        uint64 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendMultiEpoch_byOneEpoch() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize; // 1 epoch
        uint256 newDeposit = initDeposit * 2;
        uint64 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub active
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub ext: more funds claimable");
        assertEq(starting, shares, "sub ext: sub started");
        assertEq(expiring, 0, "sub ext: sub not yet expired");

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendSingleEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // 1 epoch
        uint256 newDeposit = initDeposit + rate;
        uint64 initDepositAt = epochSize + (epochSize / 10);

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "epoch 1 : all init funds claimable");
        assertEq(starting, shares, "epoch 1: sub started");
        assertEq(expiring, shares, "epoch 1: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendSingleEpoch_byOneEpoch() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // 1 epoch
        uint256 newDeposit = initDeposit + (epochSize * rate);
        uint64 initDepositAt = epochSize + (epochSize / 10);

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "epoch 1 : no funds claimable");
        assertEq(starting, shares, "epoch 1: sub started");
        assertEq(expiring, shares, "epoch 1: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub ext: partial funds claimable");
        assertEq(starting, shares, "sub ext: sub started");
        assertEq(expiring, 0, "sub ext: sub not yet expired");

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testReduceEpoch_ReduceMultiEpoch_byOneEpoch() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = initDeposit / 2; // 1 epoch
        uint64 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub init e2: partial funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, 0, "sub init e2: sub not expired");
        assertEq(e.activeSubShares(), shares, "sub init e2: sub active");

        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, initDeposit, "sub init e3: all funds claimable");
        assertEq(starting, shares, "sub init e3: sub started");
        assertEq(expiring, shares, "sub init e3: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub red e2: reduced funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, shares, "sub red e2: sub expired");

        vm.roll(initDepositAt + (1 * epochSize));
        assertEq(e.activeSubShares(), shares, "sub not expired");

        vm.roll(initDepositAt + (2 * epochSize));
        assertEq(e.activeSubShares(), 0, "sub expired");
    }

    function testReduceEpoch_ReduceMultiEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = initDeposit - rate; // 1 time unit reduced
        uint64 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub init e2: partial funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, 0, "sub init e2: sub not expired");

        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, initDeposit, "sub init e3: all funds claimable");
        assertEq(starting, shares, "sub init e3: sub started");
        assertEq(expiring, shares, "sub init e3: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub active
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub red e2: partial funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, 0, "sub red e2: sub not expired");

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, newDeposit, "sub red e3: reduced funds claimable");
        assertEq(starting, shares, "sub red e3: sub started");
        assertEq(expiring, shares, "sub red e3: sub expired");

        vm.roll(initDepositAt + (1 * epochSize));
        assertEq(e.activeSubShares(), shares, "e1: sub not expired");

        vm.roll(initDepositAt + (2 * epochSize));
        assertEq(e.activeSubShares(), shares, "e2: sub not expired");

        vm.roll(initDepositAt + (3 * epochSize));
        assertEq(e.activeSubShares(), 0, "e3: sub expired");
    }

    function testReduceEpoch_reduceMultiEpoch_cancelToOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint64 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub init e2: partial funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, 0, "sub init e2: sub not expired");

        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, initDeposit, "sub init e3: all funds claimable");
        assertEq(starting, shares, "sub init e3: sub started");
        assertEq(expiring, shares, "sub init e3: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "canceled sub still seen as active");

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, newDeposit, "sub red e1: all funds claimable");
        assertEq(starting, shares, "sub red e1: sub started");
        assertEq(expiring, shares, "sub red e1: sub expired");

        vm.roll(initDepositAt + epochSize);
        assertEq(e.activeSubShares(), 0, "e1: sub expired");
    }

    function testReduceEpoch_reduceMultiEpoch_cancelToOneTimeUnit_past() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint64 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.roll(newDepositAt);
        vm.expectRevert();
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testReduceEpoch_reduceMultiEpoch_cancelToZeroTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = 0; // to 1 time unit reduced
        uint64 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(newDepositAt);
        vm.expectRevert();
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testReduceEpoch_reduceSingleEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // just some time units
        uint256 newDeposit = initDeposit - rate; // 1 time unit reduced
        uint64 initDepositAt = epochSize + (epochSize / 10); // not epoch 0

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub init e2: all funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, shares, "sub init e2: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub red e2: all funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, shares, "sub red e2: sub not expired");

        vm.roll(initDepositAt + epochSize);
        assertEq(e.activeSubShares(), 0, "e1: sub expired");
    }

    function testReduceEpoch_reduceSingleEpoch_cancelToOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // just some time units
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint64 initDepositAt = epochSize + (epochSize / 10); // not epoch 0

        uint256 newDepositAt = initDepositAt;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub init e2: all funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, shares, "sub init e2: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub red e2: all funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, shares, "sub red e2: sub not expired");

        vm.roll(initDepositAt + epochSize);
        assertEq(e.activeSubShares(), 0, "e1: sub expired");
    }

    function testReduceEpoch_reduceSingleEpoch_cancelToOneTimeUnit_past() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // just some time units
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint64 initDepositAt = epochSize + (epochSize / 10); // not epoch 0

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.roll(newDepositAt);
        vm.expectRevert();
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testProcessEpochs_reduceEpoch(uint16 shares, uint256 initDeposit, uint256 newDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, oneTimeUnit(rate, shares), 5_000_000); // at least 2 time unit
        newDeposit = bound(newDeposit, oneTimeUnit(rate, shares), initDeposit); // at least 1 time unit
        uint64 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = bound(newDeposit, initDepositAt, newExpiresAt - 1);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, uint64(initExpiresAt / epochSize) + 1);
        assertEq(amount, initDeposit, "sub reduce: all funds claimable");
        assertEq(starting, shares, "sub reduce: sub started");
        assertEq(expiring, shares, "sub reduce: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // sub expiration was moved to a new epoch, sub needs to still be expired in old epoch
        (amount, starting, expiring) = e.scanEpochs(rate, uint64(initExpiresAt / epochSize) + 1);
        assertEq(amount, newDeposit, "sub reduce: new deposit is expired");
        assertEq(starting, shares, "sub reduce: sub started");
        assertEq(expiring, shares, "sub reduce: sub expired");

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, uint64(newExpiresAt / epochSize) + 1);
        assertEq(amount, newDeposit, "sub reduce exp: all funds claimable");
        assertEq(starting, shares, "sub reduce exp: sub started");
        assertEq(expiring, shares, "sub reduce exp: sub expired");
    }

    function testClaim(uint16 shares, uint256 initDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit =
            bound(initDeposit, oneTimeUnit(rate, shares) * epochSize, oneTimeUnit(rate, shares) * epochSize * 25);
        uint256 initDepositAt = epochSize / 10;

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
            assertEq(shares, e.activeSubShares(), "epoch 0: shares active");

            // try second claim -> no change
            amount = e.claim(rate);
            assertEq(amount, 0, "epoch 0, 2: second claim ineffective");
            assertEq(totalClaimed, e.claimed(), "epoch 0, 2: total claimed");
            assertEq(0, e.lastProcessedEpoch(), "epoch 0, 2: last processed epoch");
            assertEq(shares, e.activeSubShares(), "epoch 0, 2: shares active");
        }

        // if sub is too small to contain full epochs, we skip this check
        if (initExpiresAt / epochSize != 1) {
            // check each subsequent epoch
            for (uint64 i = 2; i <= (uint64(initExpiresAt) / epochSize); i++) {
                vm.roll(initDepositAt + (i * epochSize));

                uint256 amount = e.claim(rate);
                totalClaimed += amount;
                assertEq(amount, (rate * shares * epochSize) / 100, "epoch i: partial funds claimable");

                assertEq(totalClaimed, e.claimed(), "epoch i: total claimed");
                assertEq(i - 1, e.lastProcessedEpoch(), "epoch i: last processed epoch");
                assertEq(shares, e.activeSubShares(), "epoch i: shares active");

                // try second claim -> no change
                amount = e.claim(rate);
                assertEq(amount, 0, "epoch i, 2: second claim ineffective");
                assertEq(totalClaimed, e.claimed(), "epoch i, 2: total claimed");
                assertEq(i - 1, e.lastProcessedEpoch(), "epoch i, 2: last processed epoch");
                assertEq(shares, e.activeSubShares(), "epoch i, 2: shares active");
            }
        }

        {
            vm.roll(initExpiresAt + epochSize);

            uint256 amount = e.claim(rate);
            totalClaimed += amount;

            assertEq(totalClaimed, e.claimed(), "last epoch: total claimed");
            assertEq(totalClaimed, initDeposit, "last epoch: total claimable funds");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch: last processed epoch");
            assertEq(0, e.activeSubShares(), "last epoch: shares not active");

            // try second claim -> no change
            amount = e.claim(rate);
            assertEq(amount, 0, "last epoch, 2: second claim ineffective");
            assertEq(totalClaimed, e.claimed(), "last epoch, 2: total claimed");
            assertEq(totalClaimed, initDeposit, "last epoch, 2: total claimable funds");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch, 2: last processed epoch");
            assertEq(0, e.activeSubShares(), "last epoch, 2: shares not active");
        }
    }

    function testClaim_singleEpoch(uint16 shares, uint256 initDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, oneTimeUnit(rate, shares), oneTimeUnit(rate, shares) * (epochSize / 2));
        uint256 initDepositAt = epochSize / 10;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        // claim epoch 0
        vm.roll(initDepositAt + epochSize);

        uint256 amount = e.claim(rate);

        assertEq(amount, initDeposit, "epoch 0: partial funds claimable");

        assertEq(e.claimed(), initDeposit, "epoch 0: total amount claimed");
        assertEq(0, e.lastProcessedEpoch(), "epoch 0: last processed epoch");
        assertEq(0, e.activeSubShares(), "epoch 0: shares not active after expire");
    }

    function testClaim_single_total(uint16 shares) public {
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
            assertEq(0, e.activeSubShares(), "last epoch: shares not active after expire");
        }
    }

    function testClaim_mutliple_total(uint16 shares1, uint16 shares2) public {
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

        if (deposit1ExpiresAt > deposit2At) {
            // subs intersect
            assertEq(shares1 + shares2, e.activeSubShares(), "shares from both subs active");
        }

        vm.roll(deposit1ExpiresAt.max(deposit2ExpiresAt) + epochSize);

        e.claim(rate);

        assertEq(deposit1 + deposit2, e.claimed(), "last epoch: total funds claimed");
        assertEq(
            deposit1ExpiresAt.max(deposit2ExpiresAt) / epochSize,
            e.lastProcessedEpoch(),
            "last epoch: last processed epoch"
        );
        assertEq(0, e.activeSubShares(), "last epoch: all shares not active after expire");
    }

    function testClaim_epoch0(uint16 shares) public {
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(initDeposit, shares, rate);

        vm.expectRevert(); // cannot handle claim of epoch 0
        e.claim(rate);
    }

    function testClaim_noSubs(uint64 epoch) public {
        epoch = uint64(bound(epoch, 1, 50));

        vm.roll(epochSize * epoch);

        uint256 amount = e.claim(rate);
        assertEq(0, amount, "no funds claimed");

        assertEq(0, e.claimed(), "total funds 0");
        assertEq(epoch - 1, e.lastProcessedEpoch(), "last processed epoch advanced to previous epoch");
        assertEq(0, e.activeSubShares(), "no subs exist");
    }
}