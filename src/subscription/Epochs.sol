// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lib} from "./Lib.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title Subscription Epochs
 * @notice Epochs account for starting and expiring subscriptions
 * @dev Epochs always start from genesis
 */
struct Epoch {
    /**
     * @notice Number of expiring subscription shares
     */
    uint256 expiring;
    /**
     * @notice Number of starting subscription shares
     */
    uint256 starting; // number of starting subscription shares
    /**
     * @notice The amount of funds belonging to starting and ending subs in the epoch
     * @dev The amount is represented in internal decimals
     */
    uint256 partialFunds;
}

/**
 * @title Has Epochs Mixin interface
 * @notice Provides internal 'interface' functions of the mixin
 */
abstract contract HasEpochs {

    /**
     * @notice Provides the size of an epoch as defined in the subscription plan settings
     * @return Size of an epoch in time units
     */
    function _epochSize() internal view virtual returns (uint256);

    /**
     * @notice Provides the sequential number of the current epoch
     * @return the sequential number of the current epoch
     */
    function _currentEpoch() internal view virtual returns (uint256);

    /**
     * @notice Provides the number of active shares
     * @dev The active shares hint towards the number of active subscriptions.
     *      100 shares equal 1 non-multiplied subscription
     * @return the sequential number of the current epoch
     */
    function _activeSubShares() internal view virtual returns (uint256);

    /**
     * @notice Amount of (ever) claimed funds
     * @dev The amount is represented in internal decimals
     * @return Amount of (ever) claimed funds
     */
    function _claimed() internal view virtual returns (uint256);

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
    using Lib for uint256;

    struct EpochsStorage {
        uint256 _epochSize;
        mapping(uint256 => Epoch) _epochs;
        // number of active subscriptions with a multiplier represented as shares
        // base 100:
        // 1 Sub * 1x == 100 shares
        // 1 Sub * 2.5x == 250 shares
        uint256 _activeSubShares;
        uint256 _lastProcessedEpoch;
        uint256 _claimed;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.Epochs")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EpochsStorageLocation = 0xa37ad06674bbaa0ce562b40a47c6d9e758dfe44c585749b25d5bb38fa0f8d500;

    function _getEpochsStorage() private pure returns (EpochsStorage storage $) {
        assembly {
            $.slot := EpochsStorageLocation
        }
    }

    function __Epochs_init(uint256 epochSize) internal onlyInitializing {
        __Epochs_init_unchained(epochSize);
    }

    function __Epochs_init_unchained(uint256 epochSize) internal onlyInitializing {
        EpochsStorage storage $ = _getEpochsStorage();
        $._epochSize = epochSize;
        $._lastProcessedEpoch = _currentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    function _epochSize() internal view override returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._epochSize;
    }

    function _currentEpoch() internal view override returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return _now() / $._epochSize;
    }

    function _claimed() internal view override returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._claimed;
    }

    function _activeSubShares() internal view override returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        uint256 currentEpoch = _currentEpoch();
        uint256 _activeSubs = $._activeSubShares;

        for (uint256 i = _lastProcessedEpoch(); i < currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= $._epochs[i].expiring;
            _activeSubs += $._epochs[i].starting;
        }

        // add most recent starting subs, being optimistic
        _activeSubs += $._epochs[currentEpoch].starting;
        return _activeSubs;
    }

    function _lastProcessedEpoch() private view returns (uint256 i) {
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        EpochsStorage storage $ = _getEpochsStorage();
        if (0 == $._lastProcessedEpoch && _currentEpoch() > 1) {
            i = 0;
        } else {
            i = $._lastProcessedEpoch + 1;
        }
    }

    function _processEpochs(uint256 rate, uint256 currentEpoch)
        internal
        view
        override
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        EpochsStorage storage $ = _getEpochsStorage();
        uint256 _activeSubs = $._activeSubShares;

        for (uint256 i = _lastProcessedEpoch(); i < currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= $._epochs[i].expiring;

            // we do not apply the individual multiplier to `rate` as it is
            // included in _activeSubs, expiring, and starting subs
            amount += $._epochs[i].partialFunds + (_activeSubs * $._epochSize * rate) / Lib.MULTIPLIER_BASE;
            starting += $._epochs[i].starting;
            expiring += $._epochs[i].expiring;
            // add new subs starting in this epoch
            _activeSubs += $._epochs[i].starting;
        }
    }

    function _handleEpochsClaim(uint256 rate) internal override returns (uint256) {
        uint256 currentEpoch = _currentEpoch();
        require(currentEpoch > 1, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = _processEpochs(rate, currentEpoch);

        // delete epochs
        EpochsStorage storage $ = _getEpochsStorage();
        for (uint256 i = _lastProcessedEpoch(); i < currentEpoch; i++) {
            delete $._epochs[i];
        }

        if (starting > expiring) {
            $._activeSubShares += starting - expiring;
        } else {
            $._activeSubShares -= expiring - starting;
        }

        $._lastProcessedEpoch = currentEpoch - 1;
        $._claimed += amount;

        return amount;
    }

    function _addNewSubscriptionToEpochs(uint256 amount, uint256 shares, uint256 rate) internal override {
        uint256 now_ = _now();
        uint256 expiresAt_ = amount.expiresAt(now_, rate);

        // starting
        uint256 currentEpoch = _currentEpoch();

        EpochsStorage storage $ = _getEpochsStorage();
        $._epochs[currentEpoch].starting += shares;
        uint256 remaining = ($._epochSize - (now_ % $._epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        );
        $._epochs[currentEpoch].partialFunds += (remaining * rate);

        // ending
        uint256 expiringEpoch = expiresAt_ / $._epochSize;
        $._epochs[expiringEpoch].expiring += shares;
        $._epochs[expiringEpoch].partialFunds += (expiresAt_ - (expiringEpoch * $._epochSize)).min(
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
        EpochsStorage storage $ = _getEpochsStorage();
        {
            // when does the sub currently end?
            uint256 oldExpiringAt = oldDeposit.expiresAt(oldDepositedAt, rate);
            // update old epoch
            uint256 oldEpoch = oldExpiringAt / $._epochSize;
            $._epochs[oldEpoch].expiring -= shares;
            uint256 removable = (oldExpiringAt - ((oldEpoch * $._epochSize).max(now_))) * rate;
            $._epochs[oldEpoch].partialFunds -= removable;
        }

        // update new epoch
        uint256 newEndingBlock = newDeposit.expiresAt(newDepositedAt, rate);
        uint256 newEpoch = newEndingBlock / $._epochSize;
        $._epochs[newEpoch].expiring += shares;
        $._epochs[newEpoch].partialFunds += (newEndingBlock - ((newEpoch * $._epochSize).max(now_))) * rate;
    }
}