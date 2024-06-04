// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lib} from "./Lib.sol";
import {HasRate} from "./Rate.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract HasUserData {
    struct SubData {
        uint256 mintedAt; // mint date
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 lastDepositAt; // date of last deposit, counting only renewals of subscriptions
        // it remains untouched on withdrawals and tips
        uint256 currentDeposit; // unspent amount of tokens at lastDepositAt
        uint256 lockedAmount; // amount of funds locked
        uint256 tips; // amount of tips sent to this subscription
        uint24 multiplier;
    }

    uint256 public constant LOCK_BASE = 10_000;

    function _lock() internal view virtual returns (uint256);

    function _isActive(uint256 tokenId) internal view virtual returns (bool);

    function _expiresAt(uint256 tokenId) internal view virtual returns (uint256);

    function _deleteSubscription(uint256 tokenId) internal virtual;

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal virtual;

    // TODO amount to add to given subscription
    function _addToSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        returns (uint256 oldDeposit, uint256 newDeposit, bool reactived, uint256 subStartAt);

    function _withdrawableFromSubscription(uint256 tokenId) internal view virtual returns (uint256);

    /// @notice reduces the deposit amount of the existing subscription without changing the deposit time
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        returns (uint256 oldDeposit, uint256 newDeposit);

    function _spent(uint256 tokenId) internal view virtual returns (uint256, uint256);

    function _totalDeposited(uint256 tokenId) internal view virtual returns (uint256);

    function _multiplier(uint256 tokenId) internal view virtual returns (uint24);

    function _lastDepositedAt(uint256 tokenId) internal view virtual returns (uint256);

    function _addTip(uint256 tokenId, uint256 amount) internal virtual;

    function _tips(uint256 tokenId) internal view virtual returns (uint256);

    function _allTips() internal view virtual returns (uint256);

    function _claimedTips() internal view virtual returns (uint256);

    function _claimableTips() internal view virtual returns (uint256);

    function _claimTips() internal virtual returns (uint256);

    function _getSubData(uint256 tokenId) internal view virtual returns (SubData memory);
}

abstract contract UserData is Initializable, TimeAware, HasRate, HasUserData {
    using Lib for uint256;
    using Math for uint256;

    struct UserDataStorage {
        // locked % of deposited amount
        // 0 - 10000
        uint256 _lock;
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

    function __UserData_init(uint256 lock) internal onlyInitializing {
        __UserData_init_unchained(lock);
    }

    function __UserData_init_unchained(uint256 lock) internal onlyInitializing {
        UserDataStorage storage $ = _getUserDataStorage();
        $._lock = lock;
    }

    function _lock() internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._lock;
    }

    function _isActive(uint256 tokenId) internal view override returns (bool) {
        return _now() < _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view override returns (uint256) {
        // a subscription is active form the starting time slot (including)
        // to the calculated ending time slot (excluding)
        // active = [start, + deposit / (rate * multiplier))
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 lastDeposit = $._subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit;
        return currentDeposit_.expiresAt(uint64(lastDeposit), _multipliedRate($._subData[tokenId].multiplier));
    }

    function _deleteSubscription(uint256 tokenId) internal override {
        UserDataStorage storage $ = _getUserDataStorage();
        delete $._subData[tokenId];
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal override {
        uint256 now_ = _now();

        UserDataStorage storage $ = _getUserDataStorage();
        $._subData[tokenId].mintedAt = now_;
        $._subData[tokenId].lastDepositAt = now_;
        $._subData[tokenId].totalDeposited = amount;
        $._subData[tokenId].currentDeposit = amount;
        $._subData[tokenId].multiplier = multiplier;

        // set lockedAmount
        $._subData[tokenId].lockedAmount = ((amount * $._lock) / LOCK_BASE).adjustToRate(_multipliedRate(multiplier));
    }

    // TODO change to _extendSubscription
    function _addToSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 oldDeposit, uint256 newDeposit, bool reactived, uint256 oldLastDepositedAt)
    {
        uint256 now_ = _now();
        UserDataStorage storage $ = _getUserDataStorage();

        oldDeposit = $._subData[tokenId].currentDeposit;
        uint256 mRate = _multipliedRate(_multiplier(tokenId));

        oldLastDepositedAt = _lastDepositedAt(tokenId);
        reactived = now_ > _expiresAt(tokenId);
        if (reactived) {
            newDeposit = amount;
        } else {
            uint256 remainingDeposit = (_expiresAt(tokenId) - now_) * mRate;
            newDeposit = remainingDeposit + amount;
        }

        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].lastDepositAt = now_;
        $._subData[tokenId].totalDeposited += amount;
        $._subData[tokenId].lockedAmount = ((newDeposit * $._lock) / LOCK_BASE).adjustToRate(mRate);
    }

    function _withdrawableFromSubscription(uint256 tokenId) internal view override returns (uint256) {
        if (!_isActive(tokenId)) {
            return 0;
        }

        UserDataStorage storage $ = _getUserDataStorage();
        uint256 lastDeposit = $._subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit; // TODO normalize by rate
        uint256 lockedAmount = $._subData[tokenId].lockedAmount;
        uint256 mRate = _multipliedRate($._subData[tokenId].multiplier);
        uint256 usedBlocks = _now() - lastDeposit;

        return (currentDeposit_ - lockedAmount).min(currentDeposit_ - (usedBlocks * mRate));
    }

    /// @notice reduces the deposit amount of the existing subscription without changing the deposit time
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 oldDeposit, uint256 newDeposit)
    {
        UserDataStorage storage $ = _getUserDataStorage();
        oldDeposit = $._subData[tokenId].currentDeposit;
        newDeposit = oldDeposit - amount;
        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].totalDeposited -= amount;
    }

    function _spent(uint256 tokenId) internal view override returns (uint256, uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 totalDeposited = $._subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!_isActive(tokenId)) {
            spentAmount = totalDeposited;
        } else {
            spentAmount = totalDeposited - $._subData[tokenId].currentDeposit
                + ((_now() - $._subData[tokenId].lastDepositAt) * _multipliedRate($._subData[tokenId].multiplier));
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

    function _lastDepositedAt(uint256 tokenId) internal view override returns (uint256) {
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