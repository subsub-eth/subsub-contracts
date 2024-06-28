// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../../src/subscription/UserData.sol";

contract TestUserData is UserData {
    uint256 private rate;

    constructor(uint24 lock_, uint256 rate_) initializer {
        __UserData_init(lock_);
        rate = rate_;
    }

    function _now() internal view override returns (uint256) {
        return block.number;
    }

    function _multipliedRate(uint256) internal pure override returns (uint256) {
        revert("deprecated");
    }

    function _rate() internal view override returns (uint256) {
        return rate;
    }

    function multiplier(uint256 tokenId) public view virtual returns (uint24) {
        return _multiplier(tokenId);
    }

    function lock() public view virtual returns (uint24) {
        return _lock();
    }

    function isActive(uint256 tokenId) public view virtual returns (bool) {
        return _isActive(tokenId);
    }

    function expiresAt(uint256 tokenId) public view virtual returns (uint256) {
        return _expiresAt(tokenId);
    }

    function lastDepositedAt(uint256 tokenId) public view virtual returns (uint256) {
        return _lastDepositedAt(tokenId);
    }

    function deleteSubscription(uint256 tokenId) public virtual {
        _deleteSubscription(tokenId);
    }

    function createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier_) public virtual {
        _createSubscription(tokenId, amount, multiplier_);
    }

    function extendSubscription(uint256 tokenId, uint256 amount)
        public
        virtual
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        return _extendSubscription(tokenId, amount);
    }

    function withdrawableFromSubscription(uint256 tokenId) public view virtual returns (uint256) {
        return _withdrawableFromSubscription(tokenId);
    }

    function withdrawFromSubscription(uint256 tokenId, uint256 amount)
        public
        virtual
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        return _withdrawFromSubscription(tokenId, amount);
    }

    function spent(uint256 tokenId) public view virtual returns (uint256 spent_, uint256 unspent) {
        return _spent(tokenId);
    }

    function totalDeposited(uint256 tokenId) public view virtual returns (uint256) {
        return _totalDeposited(tokenId);
    }

    function addTip(uint256 tokenId, uint256 amount) public {
        _addTip(tokenId, amount);
    }

    function tips(uint256 tokenId) public view returns (uint256) {
        return _tips(tokenId);
    }

    function allTips() public view returns (uint256) {
        return _allTips();
    }

    function claimedTips() public view returns (uint256) {
        return _claimedTips();
    }

    function claimableTips() public view returns (uint256) {
        return _claimableTips();
    }

    function claimTips() public returns (uint256) {
        return _claimTips();
    }
}

contract UserDataTest is Test {
    using Math for uint256;

    uint24 constant BASE_MULTI = 100;
    uint24 constant MAX_MULTI = 10_000;
    uint24 constant BASE_LOCK = 10_000;
    uint24 constant MAX_LOCK = 10_000;

    TestUserData private sd;

    uint256 private tokenId;
    uint24 private lock;
    uint256 private rate;
    uint256 private _block;

    function setUp() public {
        tokenId = 1;
        lock = 100;
        rate = 10;
        _block = 1234;

        sd = new TestUserData(lock, rate);
    }

    function testAddTip(uint256 _tokenId, uint256 amount) public {
        sd.addTip(_tokenId, amount);
        assertEq(amount, sd.tips(_tokenId), "Tip added to token");
        assertEq(amount, sd.allTips(), "Tip added to contract");
        assertEq(0, sd.claimedTips(), "No tips were claimed");
    }

    function testAddTip_incrementSingleToken(uint256 _tokenId, uint64[] memory amounts) public {
        uint256 allTips = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            allTips += amounts[i];
            sd.addTip(_tokenId, amounts[i]);

            assertEq(allTips, sd.tips(_tokenId), "Tip added to token");
            assertEq(allTips, sd.allTips(), "Tip added to contract");
            assertEq(0, sd.claimedTips(), "No tips were claimed");
        }
    }

    function testAddTip_incrementContract(uint256[] memory tokenIds, uint64 amount) public {
        uint256 allTips = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            allTips += amount;
            uint256 tokenTips = sd.tips(tokenIds[i]);

            sd.addTip(tokenIds[i], amount);
            assertEq(tokenTips + amount, sd.tips(tokenIds[i]), "Tip added to token");
            assertEq(allTips, sd.allTips(), "Tip added to contract");
            assertEq(0, sd.claimedTips(), "No tips were claimed");
        }
    }

    function testClaimTips(uint256 _tokenId, uint256 amount) public {
        sd.addTip(_tokenId, amount);

        assertEq(amount, sd.claimableTips(), "all tips claimable");

        uint256 claimed = sd.claimTips();

        assertEq(amount, claimed, "all tips claimed");
        assertEq(0, sd.claimableTips(), "no more tips to claim");
        assertEq(amount, sd.allTips(), "claimed tips still accounted for");
        assertEq(amount, sd.tips(_tokenId), "claimed tips in token still accounted for");
    }

    function testClaimTips_multiple(uint256[] memory tokenIds, uint64 amount) public {
        uint256 totalAmount = 0;
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalAmount += amount;
            sd.addTip(tokenIds[i], amount);

            uint256 claimed = sd.claimTips();
            assertEq(claimed, amount, "just tipped amount equals claimed");
            totalClaimed += claimed;
            assertEq(totalAmount, totalClaimed, "all claimed tips match total tips");

            assertEq(totalClaimed, sd.allTips(), "total claimed matches all tips");
            assertEq(totalClaimed, sd.claimedTips(), "total claimed matches all claimed tips");
        }
    }

    function testCreateSub_duplicate(uint256 _tokenId) public {
        _tokenId = bound(_tokenId, 1, type(uint256).max);

        sd.createSubscription(_tokenId, 0, BASE_MULTI);

        vm.expectRevert();
        sd.createSubscription(_tokenId, 0, BASE_MULTI);
    }

    function testCreateSub_empty() public {
        uint256 amount = 0;
        uint24 multi = BASE_MULTI;

        vm.roll(_block);

        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertFalse(sd.isActive(tokenId), "token inactive");
        assertEq(sd.expiresAt(tokenId), _block, "token expires now");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "nothing to withdraw");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, 0, "nothing spent");
            assertEq(unspent, 0, "nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), 0, "nothing deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");
    }

    function testCreateSub() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: 1st block spent");
            assertEq(unspent, amount - rate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // check half way

        vm.roll(_block + ((expiresAt - _block) / 2));
        assertEq(sd.multiplier(tokenId), multi, "half: multiplier set");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            (amount / 2) - rate,
            "half: half withdrawable, minus current block"
        );
        assertTrue(sd.isActive(tokenId), "half: token active");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, (amount / 2) + rate, "half: half spent");
            assertEq(unspent, (amount / 2) - rate, "half: half unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "half: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "half: last deposit still set");

        // expire
        vm.roll(expiresAt);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit still set");
    }

    function testFuzz_CreateSub(uint256 amount, uint24 multi) public {
        multi = uint24(bound(multi, BASE_MULTI, MAX_MULTI));

        lock = uint24(bound(multi + multi, 1, MAX_LOCK));
        // more than 1 time unit amount must be deposited
        amount = bound(amount, ((rate * multi) / Lib.MULTIPLIER_BASE) + 1, type(uint128).max);

        sd = new TestUserData(lock, rate);
        uint256 blockRate = (rate * multi) / BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active, in mint block");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / BASE_LOCK).max((rate * multi) / Lib.MULTIPLIER_BASE),
            "withdrawable only unlocked or unspent amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, blockRate, "init: 1st block spent");
            assertEq(unspent, amount - blockRate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // check half way

        vm.roll(_block + ((expiresAt - _block) / 2));
        assertEq(sd.multiplier(tokenId), multi, "half: multiplier set");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount
                - (((1 + ((expiresAt - _block) / 2)) * rate * multi) / Lib.MULTIPLIER_BASE).max((amount * lock) / BASE_LOCK),
            "half: half withdrawable, minus current block"
        );
        assertTrue(sd.isActive(tokenId), "half: token active");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(
                spent, (((1 + ((expiresAt - _block) / 2)) * rate * multi) / Lib.MULTIPLIER_BASE), "half: half spent"
            );
            assertEq(
                unspent,
                amount - (((1 + ((expiresAt - _block) / 2)) * rate * multi) / Lib.MULTIPLIER_BASE),
                "half: half unspent"
            );
        }
        assertEq(sd.totalDeposited(tokenId), amount, "half: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "half: last deposit still set");

        // expire
        vm.roll(expiresAt);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit still set");
    }

    function testCreateSub_noLock() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;
        lock = 0;
        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(sd.withdrawableFromSubscription(tokenId), amount - rate, "the current block has to be paid");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block spent");
            assertEq(unspent, amount - rate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");
    }

    function testExtendSub() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block spent");
            assertEq(unspent, amount - rate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // extend sub
        uint256 extendedAt = _block + 10;
        assertGt(expiresAt, extendedAt, "not yet expired");
        vm.roll(extendedAt);

        uint256 addedAmount = 50_000;
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertFalse(reactivated, "extendedAt: subscription not reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit");
            assertEq(newDeposit, amount + addedAmount, "extendedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "extendedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "extendedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "extendedAt: token active");
        assertEq(
            sd.expiresAt(tokenId),
            _block + (((amount + addedAmount) * Lib.MULTIPLIER_BASE) / (rate * multi)),
            "extendedAt: token expires at new date"
        );

        // because the time passed is relatively small, we know that we are still within the locked amount
        {
            // remember: until extension
            uint256 spentFunds = ((extendedAt - _block) * (rate * multi)) / Lib.MULTIPLIER_BASE;
            uint256 unspentFunds = (amount + addedAmount) - spentFunds;

            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                ((amount + addedAmount) - spentFunds) - ((unspentFunds * lock) / 10_000),
                "extendedAt: withdrawable only unlocked amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, spentFunds + rate, "extendedAt: mind current block");
            assertEq(unspent, unspentFunds - rate, "extendedAt: mind current block");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "extendedAt: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // old expire
        vm.roll(expiresAt);
        assertTrue(sd.isActive(tokenId), "old expiredAt: token active");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + rate, "old expiredAt: inital deposit spent, plus current block");
            assertEq(unspent, addedAmount - rate, "old expiresAt: added deposit unspent, minux current");
        }

        // new expire
        vm.roll(expiresAt + ((addedAmount * Lib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "last deposit still unchanged");
    }

    function testFuzz_ExtendSub(uint256 amount, uint24 multi) public {
        multi = uint24(bound(multi, BASE_MULTI, MAX_MULTI));

        lock = uint24(bound(multi + multi, 0, MAX_LOCK));

        // more than 1 time unit amount must be deposited
        amount = bound(amount, ((rate * multi) / Lib.MULTIPLIER_BASE) + 1, type(uint128).max);

        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / BASE_LOCK).max((rate * multi) / Lib.MULTIPLIER_BASE),
            "withdrawable only unlocked or unspent amount"
        );

        // extend sub
        uint256 extendedAt = (bound(amount, _block, expiresAt - 1));
        assertGe(expiresAt, extendedAt, "not yet expired");
        vm.roll(extendedAt);

        uint256 addedAmount = bound(amount, 0, type(uint128).max - 1);
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertFalse(reactivated, "extendedAt: subscription not reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit");
            assertEq(newDeposit, amount + addedAmount, "extendedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "extendedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "extendedAt: multiplier unchanged");
        assertEq(
            sd.expiresAt(tokenId),
            _block + ((amount + addedAmount) * Lib.MULTIPLIER_BASE) / (rate * multi),
            "extendedAt: token expires at new date"
        );
        assertTrue(sd.isActive(tokenId), "extendedAt: token active");

        {
            uint256 total = amount + addedAmount;
            console.log("total", total);
            uint256 spentFunds = ((1 + extendedAt - _block) * (rate * multi)) / Lib.MULTIPLIER_BASE;
            console.log("spent", spentFunds);
            uint256 usedFunds = ((extendedAt - _block) * (rate * multi)) / Lib.MULTIPLIER_BASE;
            uint256 lockedFunds = (((total - usedFunds) * lock) / BASE_LOCK) + usedFunds;


            console.log("locked", lockedFunds);

            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                (total - spentFunds).min(total - lockedFunds),
                "extendedAt: withdrawable only unlocked or unspent amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(
                spent,
                ((1 + extendedAt - _block) * (rate * multi)) / Lib.MULTIPLIER_BASE,
                "extendedAt: spent, mind current block, higher precision"
            );
            assertEq(
                unspent,
                (amount + addedAmount) - ((1 + extendedAt - _block) * (rate * multi)) / Lib.MULTIPLIER_BASE,
                "extendedAt: unspent, mind current block, higher precision"
            );
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "extendedAt: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // new expire
        vm.roll(_block + (((amount + addedAmount) * Lib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "expired: all in total deposited");
    }

    function testExtendSub_unlocked() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        // extend sub
        uint256 extendedAt = _block + 2_000;
        assertGt(expiresAt, extendedAt, "not yet expired");
        vm.roll(extendedAt);

        uint256 addedAmount = 50_000;
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertFalse(reactivated, "extendedAt: subscription not reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit");
            assertEq(newDeposit, amount + addedAmount, "extendedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "extendedAt: init deposit unchanged");
        }

        assertTrue(sd.isActive(tokenId), "extendedAt: token active");
        assertEq(
            sd.expiresAt(tokenId),
            expiresAt + ((addedAmount * Lib.MULTIPLIER_BASE) / (rate * multi)),
            "extendedAt: token expires now"
        );

        // because the time passed exceeds the original locked amount of funds, the locked amount is updated
        {
            // we do not mind that the block of the extension is spent
            uint256 spentFunds = ((extendedAt - _block) * (rate * multi)) / Lib.MULTIPLIER_BASE;
            uint256 unspentFunds = (amount + addedAmount) - spentFunds;

            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                ((amount + addedAmount) - spentFunds) - ((unspentFunds * lock) / 10_000),
                "extendedAt: withdrawable, updated locked amount, only unspent amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, spentFunds + rate, "extendedAt: until current block amount spent");
            assertEq(unspent, unspentFunds - rate, "extendedAt: until current block unspent");
        }
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // new expire
        // old expire + new amount
        vm.roll(expiresAt + ((addedAmount * Lib.MULTIPLIER_BASE) / (rate * multi)));

        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all funds spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
    }

    function testExtendSub_reactivate() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        // extend sub, far in the future
        uint256 extendedAt = _block + 1_000_000;
        assertLt(expiresAt, extendedAt, "subscription expired");
        vm.roll(extendedAt);
        assertFalse(sd.isActive(tokenId), "token expired before extending");

        uint256 addedAmount = 50_000;
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertTrue(reactivated, "extendedAt: subscription reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit is the amount from the previous sub streak");
            assertEq(newDeposit, addedAmount, "extendedAt: new deposit, restarted");
            assertEq(depositedAt, extendedAt, "extendedAt: init deposit updated");
        }

        assertEq(sd.multiplier(tokenId), multi, "extendedAt: multiplier unchanged");
        assertTrue(sd.isActive(tokenId), "extendedAt: token active");
        assertEq(
            sd.expiresAt(tokenId),
            extendedAt + ((addedAmount * Lib.MULTIPLIER_BASE) / (rate * multi)),
            "extendedAt: token expires at new date"
        );

        {
            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                addedAmount - ((addedAmount * lock) / 10_000),
                "extendedAt: withdrawable only part of added amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + rate, "extendedAt: old amount spent, plus current block");
            assertEq(unspent, addedAmount - rate, "extendedAt: new amount unspent, minus current block");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "extendedAt: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // new expire
        vm.roll(extendedAt + ((addedAmount * Lib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.multiplier(tokenId), multi, "expired: multiplier unchanged");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "last deposit unchanged");
    }

    function testReduceSub() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block");
            assertEq(unspent, amount - rate, "init: except first block unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // reduce sub
        uint256 reducedAt = _block + 1;
        assertGt(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        uint256 reducedAmount = 50_000;
        uint256 newExpiresAt = _block + (((amount - reducedAmount) * Lib.MULTIPLIER_BASE) / (rate * multi));
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "reducedAt: token active");
        assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000) - reducedAmount,
            "reducedAt: locked amount unchanged"
        );

        vm.roll(newExpiresAt);
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
    }

    function testReduceSub_cancel() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block");
            assertEq(unspent, amount - rate, "init: except first block unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // reduce sub
        uint256 reducedAt = _block + 1;
        assertGt(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        uint256 reducedAmount = sd.withdrawableFromSubscription(tokenId);
        uint256 newExpiresAt = _block + (((amount - reducedAmount) * Lib.MULTIPLIER_BASE) / (rate * multi));
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "reducedAt: token active");
        assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000) - reducedAmount,
            "reducedAt: locked amount unchanged"
        );

        vm.roll(newExpiresAt);
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
    }

    function testReduceSub_cancel_noLock() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;
        lock = 0;
        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * Lib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(sd.withdrawableFromSubscription(tokenId), amount - rate, "all funds except current block withdrawable");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block");
            assertEq(unspent, amount - rate, "init: except first block unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // reduce sub, token becomes inactive in the following block
        uint256 reducedAt = _block + 1;
        assertGt(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        assertEq(sd.withdrawableFromSubscription(tokenId), amount - (rate * 2), "only 2 blocks are paid");
        uint256 reducedAmount = sd.withdrawableFromSubscription(tokenId);
        uint256 newExpiresAt = _block + (((amount - reducedAmount) * Lib.MULTIPLIER_BASE) / (rate * multi));
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "reducedAt: token is still active in the cancelation block");
        assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "reducedAt: nothing to withdraw");

        // token becomes inactive in the following block
        vm.roll(reducedAt + 1);
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
    }
}