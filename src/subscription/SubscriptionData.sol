// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionLib} from "./SubscriptionLib.sol";
import {Rate} from "./Rate.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

abstract contract SubscriptionData is Initializable, TimeAware, Rate {
    using SubscriptionLib for uint256;
    using Math for uint256;

    struct SubData {
        uint256 mintedAt; // mint date
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 lastDepositAt; // date of last deposit, counting only renewals of subscriptions
        // it remains untouched on withdrawals and tips
        uint256 currentDeposit; // unspent amount of tokens at lastDepositAt
        uint256 lockedAmount; // amount of funds locked
        // TODO change type
        uint256 multiplier;
    }

    uint256 public constant LOCK_BASE = 10_000;

    // locked % of deposited amount
    // 0 - 10000
    uint256 private _lock;
    mapping(uint256 => SubData) private _subData;

    function __SubscriptionData_init(uint256 lock, uint256 rate) internal onlyInitializing {
        __Rate_init(rate);
        __SubscriptionData_init_unchained(lock);
    }

    function __SubscriptionData_init_unchained(uint256 lock) internal onlyInitializing {
        _lock = lock;
    }

    function _isActive(uint256 tokenId) internal view returns (bool) {
        return _now() < _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view returns (uint256) {
        // a subscription is active form the starting time slot (including)
        // to the calculated ending time slot (excluding)
        // active = [start, + deposit / rate)
        uint256 lastDeposit = _subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = _subData[tokenId].currentDeposit;
        return currentDeposit_.expiresAt(lastDeposit, _multipliedRate(_subData[tokenId].multiplier));
    }

    function _deleteSubscription(uint256 tokenId) internal {
        delete _subData[tokenId];
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint256 multiplier) internal {
        uint256 now_ = _now();

        _subData[tokenId].mintedAt = now_;
        _subData[tokenId].lastDepositAt = now_;
        _subData[tokenId].totalDeposited = amount;
        _subData[tokenId].currentDeposit = amount;
        _subData[tokenId].multiplier = multiplier;

        // set lockedAmount
        _subData[tokenId].lockedAmount = ((amount * _lock) / LOCK_BASE).adjustToRate(_multipliedRate(multiplier));
    }

    function _addToSubscription(uint256 tokenId, uint256 amount)
        internal
        returns (uint256 oldDeposit, uint256 newDeposit, bool reactived, uint256 oldLastDepositedAt)
    {
        uint256 now_ = _now();

        oldDeposit = _subData[tokenId].currentDeposit;
        uint256 mRate = _multipliedRate(_multiplier(tokenId));

        oldLastDepositedAt = _lastDepositedAt(tokenId);
        reactived = now_ > _expiresAt(tokenId);
        if (reactived) {
            newDeposit = amount;
        } else {
            uint256 remainingDeposit = (_expiresAt(tokenId) - now_) * mRate;
            newDeposit = remainingDeposit + amount;
        }

        _subData[tokenId].currentDeposit = newDeposit;
        _subData[tokenId].lastDepositAt = now_;
        _subData[tokenId].totalDeposited += amount;
        _subData[tokenId].lockedAmount = ((newDeposit * _lock) / LOCK_BASE).adjustToRate(mRate);
    }

    function _withdrawableFromSubscription(uint256 tokenId) internal view returns (uint256) {
        if (!_isActive(tokenId)) {
            return 0;
        }

        uint256 lastDeposit = _subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = _subData[tokenId].currentDeposit;
        uint256 lockedAmount = _subData[tokenId].lockedAmount;
        uint256 mRate = _multipliedRate(_subData[tokenId].multiplier);
        uint256 usedBlocks = _now() - lastDeposit;

        return (currentDeposit_ - lockedAmount).min(currentDeposit_ - (usedBlocks * mRate));
    }

    /// @notice reduces the deposit amount of the existing subscription without changing the deposit time
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        returns (uint256 oldDeposit, uint256 newDeposit)
    {
        oldDeposit = _subData[tokenId].currentDeposit;
        newDeposit = oldDeposit - amount;
        _subData[tokenId].currentDeposit = newDeposit;
        _subData[tokenId].totalDeposited -= amount;
    }

    function _spent(uint256 tokenId) internal view returns (uint256, uint256) {
        uint256 totalDeposited = _subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!_isActive(tokenId)) {
            spentAmount = totalDeposited;
        } else {
            spentAmount = totalDeposited - _subData[tokenId].currentDeposit
                + ((_now() - _subData[tokenId].lastDepositAt) * _multipliedRate(_subData[tokenId].multiplier));
        }

        uint256 unspentAmount = totalDeposited - spentAmount;

        return (spentAmount, unspentAmount);
    }

    function _totalDeposited(uint256 tokenId) internal view returns (uint256) {
        return _subData[tokenId].totalDeposited;
    }

    function _multiplier(uint256 tokenId) internal view returns (uint256) {
        return _subData[tokenId].multiplier;
    }

    function _lastDepositedAt(uint256 tokenId) internal view returns (uint256) {
        return _subData[tokenId].lastDepositAt;
    }

    function _incrementTotalDeposited(uint256 tokenId, uint256 amount) internal {
        _subData[tokenId].totalDeposited += amount;
    }

    function _getSubData(uint256 tokenId) internal view returns (SubData memory) {
        return _subData[tokenId];
    }

    // TODO _gap
}
