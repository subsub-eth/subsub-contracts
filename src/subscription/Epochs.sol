// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionLib} from "./SubscriptionLib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

// epochs always start from genesis
struct Epoch {
    uint256 expiring; // number of expiring subscription shares
    uint256 starting; // number of starting subscription shares
    uint256 partialFunds; // the amount of funds belonging to starting and ending subs in the epoch
}

abstract contract HasEpochs {
    function _epochSize() internal view virtual returns (uint256);

    function _currentEpoch() internal view virtual returns (uint256);

    function _getActiveSubShares() internal view virtual returns (uint256);

    function _processEpochs(uint256 rate, uint256 currentEpoch)
        internal
        view
        virtual
        returns (uint256 amount, uint256 starting, uint256 expiring);

    function _handleEpochsClaim(uint256 rate) internal virtual returns (uint256);

    function _addNewSubscriptionToEpochs(uint256 amount, uint256 shares, uint256 rate) internal virtual;

    /// @notice moves the subscription based on the
    function _moveSubscriptionInEpochs(
        uint256 oldDepositedAt,
        uint256 oldDeposit,
        uint256 newDepositedAt,
        uint256 newDeposit,
        uint256 shares,
        uint256 rate
    ) internal virtual;
}

abstract contract Epochs is Initializable, TimeAware, HasEpochs {
    using Math for uint256;
    using SubscriptionLib for uint256;

    uint256 private __epochSize;
    mapping(uint256 => Epoch) private _epochs;

    // number of active subscriptions with a multiplier represented as shares
    // base 100:
    // 1 Sub * 1x == 100 shares
    // 1 Sub * 2.5x == 250 shares
    uint256 private _activeSubShares;

    uint256 private __lastProcessedEpoch;

    function __Epochs_init(uint256 epochSize) internal onlyInitializing {
        __Epochs_init_unchained(epochSize);
    }

    function __Epochs_init_unchained(uint256 epochSize) internal onlyInitializing {
        __epochSize = epochSize;
        __lastProcessedEpoch = _currentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    function _epochSize() internal view override returns (uint256) {
        return __epochSize;
    }

    function _currentEpoch() internal view override returns (uint256) {
        return _now() / __epochSize;
    }

    function _getActiveSubShares() internal view override returns (uint256) {
        return _activeSubShares;
    }

    function _lastProcessedEpoch() private view returns (uint256 i) {
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        if (0 == __lastProcessedEpoch && _currentEpoch() > 1) {
            i = 0;
        } else {
            i = __lastProcessedEpoch + 1;
        }
    }

    function _processEpochs(uint256 rate, uint256 currentEpoch)
        internal
        view
        override
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        uint256 _activeSubs = _activeSubShares;

        for (uint256 i = _lastProcessedEpoch(); i < currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= _epochs[i].expiring;

            // we do not apply the individual multiplier to `rate` as it is
            // included in _activeSubs, expiring, and starting subs
            amount += _epochs[i].partialFunds + (_activeSubs * __epochSize * rate) / SubscriptionLib.MULTIPLIER_BASE;
            starting += _epochs[i].starting;
            expiring += _epochs[i].expiring;
            // add new subs starting in this epoch
            _activeSubs += _epochs[i].starting;
        }
    }

    function _handleEpochsClaim(uint256 rate) internal override returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        require(currentEpoch > 1, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = _processEpochs(rate, currentEpoch);

        // delete epochs
        for (uint256 i = _lastProcessedEpoch(); i < currentEpoch; i++) {
            delete _epochs[i];
        }

        if (starting > expiring) {
            _activeSubShares += starting - expiring;
        } else {
            _activeSubShares -= expiring - starting;
        }

        __lastProcessedEpoch = currentEpoch - 1;

        return amount;
    }

    function _addNewSubscriptionToEpochs(uint256 amount, uint256 shares, uint256 rate) internal override {
        uint256 now_ = _now();
        uint256 expiresAt_ = amount.expiresAt(now_, rate);

        // starting
        uint256 currentEpoch = _currentEpoch();
        _epochs[currentEpoch].starting += shares;
        uint256 remaining = (__epochSize - (now_ % __epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        );
        _epochs[currentEpoch].partialFunds += (remaining * rate);

        // ending
        uint256 expiringEpoch = expiresAt_ / __epochSize;
        _epochs[expiringEpoch].expiring += shares;
        _epochs[expiringEpoch].partialFunds += (expiresAt_ - (expiringEpoch * __epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        ) * rate;
    }

    /// @notice moves the subscription based on the
    function _moveSubscriptionInEpochs(
        uint256 oldDepositedAt,
        uint256 oldDeposit,
        uint256 newDepositedAt,
        uint256 newDeposit,
        uint256 shares,
        uint256 rate
    ) internal override {
        uint256 now_ = _now();
        {
            // when does the sub currently end?
            uint256 oldExpiringAt = oldDeposit.expiresAt(oldDepositedAt, rate);
            // update old epoch
            uint256 oldEpoch = oldExpiringAt / __epochSize;
            _epochs[oldEpoch].expiring -= shares;
            uint256 removable = (oldExpiringAt - ((oldEpoch * __epochSize).max(now_))) * rate;
            _epochs[oldEpoch].partialFunds -= removable;
        }

        // update new epoch
        uint256 newEndingBlock = newDeposit.expiresAt(newDepositedAt, rate);
        uint256 newEpoch = newEndingBlock / __epochSize;
        _epochs[newEpoch].expiring += shares;
        _epochs[newEpoch].partialFunds += (newEndingBlock - ((newEpoch * __epochSize).max(now_))) * rate;
    }

    // TODO _gap
}
