// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lib} from "./Lib.sol";
import {HasRate} from "./Rate.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract HasUserData {
    struct SubData {
        uint24 multiplier;
        uint64 mintedAt; // mint date
        uint64 streakStartedAt; // start of a new subscription streak (on mint / on renewal after expired)
        uint64 lastDepositAt; // date of last deposit, counting only renewals of subscriptions
        // it remains untouched on withdrawals and tips
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 currentDeposit; // deposit since streakStartedAt, resets with streakStartedAt
        uint256 lockedAmount; // amount of locked funds as of lastDepositAt
        uint256 tips; // amount of tips sent to this subscription
    }

    uint24 public constant LOCK_BASE = 10_000; // == 100%

    /**
     * @notice the percentage of unspent funds that are locked on a subscriber deposit
     * @return the percentage of unspent funds being locked on subscriber deposit
     */
    function _lock() internal view virtual returns (uint24);

    /**
     * @notice checks the status of a subscription
     * @dev a subscription is active if it has not expired yet, now < expiration date, excluding the expiration date
     * @param tokenId subscription identifier
     * @return active status
     */
    function _isActive(uint256 tokenId) internal view virtual returns (bool);

    /**
     * @notice returns the time unit at which a given subscription expires
     * @param tokenId subscription identifier
     * @return expiration date
     */
    function _expiresAt(uint256 tokenId) internal view virtual returns (uint64);

    /**
     * @notice deletes a subscription and all its data
     * @param tokenId subscription identifier
     */
    function _deleteSubscription(uint256 tokenId) internal virtual;

    /**
     * @notice creates a new subscription using the given token id during mint
     * @dev the subscription cannot exist in UserData storage before. The multiplier cannot be changed after this call.
     * @param tokenId new identifier of the subscription
     * @param amount amount to deposit into the new subscription
     * @param multiplier multiplier that is applied to the rate in this subscription
     */
    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal virtual;

    /**
     * @notice adds the given amount to an existing subscription
     * @dev the subscription is identified by the tokenId. It may be expired.
     * The return values describe the state of the subscription and the coordinates and changes of the current subscription streak.
     * If a subscription was expired before extending, a new subscription streak is started with a new depositedAt date.
     * @param tokenId subscription identifier
     * @param amount amount to add to the given subscription
     * @return depositedAt start date of the current subscription streak
     * @return oldDeposit deposited amount counting from the depositedAt date before extension
     * @return newDeposit deposited amount counting from the depositedAt data after extension
     * @return reactivated flag if the subscription was expired and thus a new subscription streak is started
     */
    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        returns (uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated);

    /**
     * @notice returns the amount that can be withdrawn from a given subscription
     * @dev the subscription has to be active and contain unspent and unlocked funds
     * @param tokenId subscription identifier
     * @return the withdrawable amount
     */
    function _withdrawableFromSubscription(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice reduces the deposit amount of the existing subscription without changing the deposit time / start time of the current subscription streak
     * @dev the subscription may not be expired and the funds that can be withdrawn have to be unspent and unlocked
     * @param tokenId subscription identifier
     * @param amount amount to withdraw from the subscription
     * @return depositedAt start date of the current subscription streak
     * @return oldDeposit deposited amount counting from the depositedAt date before extension
     * @return newDeposit deposited amount counting from the depositedAt data after extension
     */
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        returns (uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit);

    /**
     * @notice returns the amount of total spent and yet unspent funds in the subscription, excluding tips
     * @dev in an active subscription, the current time unit is considered spent in order to prevent
     * subscribing and withdrawing within the same transaction and having an active sub without paying for
     * at least one time unit
     * @param tokenId subscription identifier
     * @return spent the spent amount
     * @return unspent the unspent amount left in the subscription
     */
    function _spent(uint256 tokenId) internal view virtual returns (uint256 spent, uint256 unspent);

    /**
     * @notice returns the amount of total deposited funds in a given subscription.
     * @dev this includes unspent and/or withdrawable funds.
     * @param tokenId subscription identifier
     * @return the total deposited amount
     */
    function _totalDeposited(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice returns the applied multiplier of a given subscription
     * @param tokenId subscription identifier
     * @return the multiplier base 100 == 1x
     */
    function _multiplier(uint256 tokenId) internal view virtual returns (uint24);

    /**
     * @notice returns the date at which the last deposit for a given subscription took place
     * @dev this value lies within the current or last subscription streak range and does not change on withdrawals
     * @param tokenId subscription identifier
     * @return the time unit date of the last deposit
     */
    function _lastDepositedAt(uint256 tokenId) internal view virtual returns (uint64);

    /**
     * @notice adds the given amount of funds to the tips of a subscription
     * @param tokenId subscription identifier
     * @param amount tip amount
     */
    function _addTip(uint256 tokenId, uint256 amount) internal virtual;

    /**
     * @notice returns the amount of tips placed in the given subscription
     * @param tokenId subscription identifier
     * @return the total amount of tips
     */
    function _tips(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice returns the amount of all tips placed in this contract
     * @return the total amount of tips in this contract
     */
    function _allTips() internal view virtual returns (uint256);

    /**
     * @notice returns the amount of tips that were claimed from this contract
     * @return the total amount of tips claimed from this contract
     */
    function _claimedTips() internal view virtual returns (uint256);

    /**
     * @notice returns the amount of tips that can be claimed from this contract
     * @dev returns the amount of not yet claimed tips
     * @return the amount of tips claimable from this contract
     */
    function _claimableTips() internal view virtual returns (uint256);

    /**
     * @notice claims the available tips from this contract
     * @return the amount of tips that were claimed by this call
     */
    function _claimTips() internal virtual returns (uint256);

    /**
     * @notice returns the internal storage struct of a given subscription
     * @param tokenId subscription identifier
     * @return the internal subscription data representation
     */
    function _getSubData(uint256 tokenId) internal view virtual returns (SubData memory);
}

abstract contract UserData is Initializable, TimeAware, HasRate, HasUserData {
    using Lib for uint256;
    using Math for uint256;

    struct UserDataStorage {
        // locked % of deposited amount
        // 0 - 10000
        uint24 _lock;
        mapping(uint256 => SubData) _subData;
        // amount of tips EVER sent to the contract, the value only increments
        uint256 _allTips;
        // amount of tips EVER claimed from the contract, the value only increments
        uint256 _claimedTips;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.UserData")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UserDataStorageLocation =
        0x759c70339345f5b3443b65fe6ae2d943782a2a023089a4692e3f21ca7befef00;

    function _getUserDataStorage() private pure returns (UserDataStorage storage $) {
        assembly {
            $.slot := UserDataStorageLocation
        }
    }

    function __UserData_init(uint24 lock) internal onlyInitializing {
        __UserData_init_unchained(lock);
    }

    function __UserData_init_unchained(uint24 lock) internal onlyInitializing {
        UserDataStorage storage $ = _getUserDataStorage();
        $._lock = lock;
    }

    function _lock() internal view override returns (uint24) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._lock;
    }

    function _isActive(uint256 tokenId) internal view override returns (bool) {
        return _now() < _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view override returns (uint64) {
        // a subscription is active form the starting time slot (including)
        // to the calculated ending time slot (excluding)
        // active = [start, + deposit / (rate * multiplier))
        UserDataStorage storage $ = _getUserDataStorage();
        uint64 depositAt = $._subData[tokenId].streakStartedAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit;

        return depositAt + currentDeposit_.validFor(_rate(), $._subData[tokenId].multiplier);
    }

    function _deleteSubscription(uint256 tokenId) internal override {
        UserDataStorage storage $ = _getUserDataStorage();
        delete $._subData[tokenId];
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal override {
        uint64 now_ = _now();

        UserDataStorage storage $ = _getUserDataStorage();
        require($._subData[tokenId].mintedAt == 0, "Subscription already exists");

        // set initially and never change
        $._subData[tokenId].multiplier = multiplier;
        $._subData[tokenId].mintedAt = now_;

        // init new subscription streak
        $._subData[tokenId].streakStartedAt = now_;
        $._subData[tokenId].lastDepositAt = now_;
        $._subData[tokenId].totalDeposited = amount;
        $._subData[tokenId].currentDeposit = amount;

        // set lockedAmount
        // the locked amount is rounded down, it is in favor of the subscriber
        $._subData[tokenId].lockedAmount = (amount * $._lock) / LOCK_BASE;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        uint64 now_ = _now();
        UserDataStorage storage $ = _getUserDataStorage();

        oldDeposit = $._subData[tokenId].currentDeposit;

        // TODO direct access
        reactivated = now_ > _expiresAt(tokenId);
        if (reactivated) {
            // subscrption was expired and is being reactivated
            newDeposit = amount;
            // start new subscription streak
            $._subData[tokenId].streakStartedAt = now_;
            $._subData[tokenId].lockedAmount = (newDeposit * $._lock) / LOCK_BASE;
        } else {
            // extending active subscription
            uint256 remainingDeposit = oldDeposit
            // spent amount
            - (
                ((now_ - $._subData[tokenId].streakStartedAt) * (_rate() * $._subData[tokenId].multiplier))
                    / Lib.MULTIPLIER_BASE
            );

            // deposit is counted from streakStartedAt
            newDeposit = oldDeposit + amount;

            // locked amount is counted from lastDepositAt
            $._subData[tokenId].lockedAmount = ((remainingDeposit + amount) * $._lock) / LOCK_BASE;
        }

        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].lastDepositAt = now_;
        $._subData[tokenId].totalDeposited += amount;

        depositedAt = $._subData[tokenId].streakStartedAt;
    }

    function _withdrawableFromSubscription(uint256 tokenId) internal view override returns (uint256) {
        if (!_isActive(tokenId)) {
            return 0;
        }

        UserDataStorage storage $ = _getUserDataStorage();

        uint256 lastDepositAt = $._subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit;

        // locked + spent up until last deposit
        uint256 lockedAmount = $._subData[tokenId].lockedAmount
            + (
                ((lastDepositAt - $._subData[tokenId].streakStartedAt) * (_rate() * $._subData[tokenId].multiplier))
                    / Lib.MULTIPLIER_BASE
            );

        // the current block is spent, thus +1
        uint256 spentFunds = (
            (1 + _now() - $._subData[tokenId].streakStartedAt) * (_rate() * $._subData[tokenId].multiplier)
        ) / Lib.MULTIPLIER_BASE;

        return (currentDeposit_ - lockedAmount).min(currentDeposit_ - (spentFunds).min(currentDeposit_));
    }

    /// @notice reduces the deposit amount of the existing subscription without changing the deposit time
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        require(amount <= _withdrawableFromSubscription(tokenId), "Withdraw amount too large");

        UserDataStorage storage $ = _getUserDataStorage();
        oldDeposit = $._subData[tokenId].currentDeposit;
        newDeposit = oldDeposit - amount;
        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].totalDeposited -= amount;

        // locked amount and last depositedAt remain unchanged

        depositedAt = $._subData[tokenId].streakStartedAt;
    }

    function _spent(uint256 tokenId) internal view override returns (uint256, uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 totalDeposited = $._subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!_isActive(tokenId)) {
            spentAmount = totalDeposited;
        } else {
            spentAmount = (totalDeposited - $._subData[tokenId].currentDeposit)
            // TODO fix rate
            + (
                ((1 + _now() - $._subData[tokenId].streakStartedAt) * _rate() * $._subData[tokenId].multiplier)
                    / Lib.MULTIPLIER_BASE
            ).min($._subData[tokenId].currentDeposit);
        }

        uint256 unspentAmount = totalDeposited - spentAmount;

        return (spentAmount, unspentAmount);
    }

    function _totalDeposited(uint256 tokenId) internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].totalDeposited;
    }

    function _multiplier(uint256 tokenId) internal view override returns (uint24) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].multiplier;
    }

    function _lastDepositedAt(uint256 tokenId) internal view override returns (uint64) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].lastDepositAt;
    }

    function _addTip(uint256 tokenId, uint256 amount) internal override {
        UserDataStorage storage $ = _getUserDataStorage();
        // TODO change me
        $._subData[tokenId].tips += amount;
        $._allTips += amount;
    }

    function _tips(uint256 tokenId) internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].tips;
    }

    function _allTips() internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._allTips;
    }

    function _claimedTips() internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._claimedTips;
    }

    function _claimableTips() internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._allTips - $._claimedTips;
    }

    function _claimTips() internal override returns (uint256 claimable) {
        UserDataStorage storage $ = _getUserDataStorage();
        claimable = $._allTips - $._claimedTips;
        $._claimedTips = $._allTips;
    }

    function _getSubData(uint256 tokenId) internal view override returns (SubData memory) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId];
    }
}