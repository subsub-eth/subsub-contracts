// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionLib} from "./SubscriptionLib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

// epochs always start from genesis
struct Epoch {
    uint256 expiring; // number of expiring subscriptions
    uint256 starting; // number of starting subscriptions
    uint256 partialFunds; // the amount of funds belonging to starting and ending subs in the epoch
}

abstract contract Epochs is Initializable, TimeAware {
    using Math for uint256;
    using SubscriptionLib for uint256;

    uint256 private _epochSize;
    mapping(uint256 => Epoch) private _epochs;

    // number of active subscriptions with a multiplier represented as shares
    // base 100:
    // 1 Sub * 1x == 100 shares
    // 1 Sub * 2.5x == 250 shares
    uint256 private _activeSubShares;

    uint256 private _lastProcessedEpoch;

    function __Epochs_init(uint256 epochSize) internal onlyInitializing {
        __Epochs_init_unchained(epochSize);
    }

    function __Epochs_init_unchained(uint256 epochSize) internal onlyInitializing {
        _epochSize = epochSize;
        _lastProcessedEpoch = _getCurrentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    // TODO rename, add leading underscore due to being an internal func
    function _getCurrentEpoch() internal view returns (uint256) {
        return _now() / _epochSize;
    }

    function _getActiveSubShares() internal view returns (uint256) {
        return _activeSubShares;
    }

    function lastProcessedEpoch() internal view returns (uint256 i) {
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        if (0 == _lastProcessedEpoch && _getCurrentEpoch() > 1) {
            i = 0;
        } else {
            i = _lastProcessedEpoch + 1;
        }
    }

    function processEpochs(uint256 rate, uint256 currentEpoch)
        internal
        view
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        uint256 _activeSubs = _activeSubShares;

        for (uint256 i = lastProcessedEpoch(); i < currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= _epochs[i].expiring;

            // we do not apply the individual multiplier to `rate` as it is
            // included in _activeSubs, expiring, and starting subs
            // TODO does the constant get inlined?
            amount += _epochs[i].partialFunds + (_activeSubs * _epochSize * rate) / SubscriptionLib.MULTIPLIER_BASE;
            starting += _epochs[i].starting;
            expiring += _epochs[i].expiring;

            // add new subs starting in this epoch
            _activeSubs += _epochs[i].starting;
        }
    }

    function handleEpochsClaim(uint256 rate) internal returns (uint256) {
        uint256 _currentEpoch = _getCurrentEpoch();
        require(_currentEpoch > 1, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = processEpochs(rate, _currentEpoch);

        // delete epochs
        // TODO: copy processEpochs function body to decrease gas?
        for (uint256 i = lastProcessedEpoch(); i < _currentEpoch; i++) {
            delete _epochs[i];
        }

        if (starting > expiring) {
            _activeSubShares += starting - expiring;
        } else {
            _activeSubShares -= expiring - starting;
        }

        _lastProcessedEpoch = _currentEpoch - 1;

        return amount;
    }

    function addNewSubscriptionToEpochs(uint256 amount, uint256 multiplier, uint256 multipliedRate, uint256 now_)
        internal
    {
        uint256 expiresAt_ = amount.expiresAt(now_, multipliedRate);

        // starting
        uint256 _currentEpoch = _getCurrentEpoch();
        _epochs[_currentEpoch].starting += multiplier;
        uint256 remaining = (_epochSize - (now_ % _epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        );
        _epochs[_currentEpoch].partialFunds += (remaining * multipliedRate);

        // ending
        uint256 expiringEpoch = expiresAt_ / _epochSize;
        _epochs[expiringEpoch].expiring += multiplier;
        _epochs[expiringEpoch].partialFunds += (expiresAt_ - (expiringEpoch * _epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        ) * multipliedRate;
    }

    function moveSubscriptionInEpochs(
        uint256 _lastDepositAt,
        uint256 _oldDeposit,
        uint256 _newDeposit,
        uint256 multiplier,
        uint256 multipliedRate,
        uint256 now_
    ) internal {
        // when does the sub currently end?
        uint256 oldExpiringAt = _oldDeposit.expiresAt(_lastDepositAt, multipliedRate);
        // update old epoch
        uint256 oldEpoch = oldExpiringAt / _epochSize;
        _epochs[oldEpoch].expiring -= multiplier;
        uint256 removable = (oldExpiringAt - ((oldEpoch * _epochSize).max(now_))) * multipliedRate;
        _epochs[oldEpoch].partialFunds -= removable;

        // update new epoch
        uint256 newEndingBlock = _newDeposit.expiresAt(_lastDepositAt, multipliedRate);
        uint256 newEpoch = newEndingBlock / _epochSize;
        _epochs[newEpoch].expiring += multiplier;
        _epochs[newEpoch].partialFunds += (newEndingBlock - ((newEpoch * _epochSize).max(now_))) * multipliedRate;
    }

    // TODO _gap
}
