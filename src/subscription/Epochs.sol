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
    function _epochSize() internal view virtual returns (uint64);

    /**
     * @notice Provides the sequential number of the current epoch
     * @return the sequential number of the current epoch
     */
    function _currentEpoch() internal view virtual returns (uint64);

    /**
     * @notice Provides the last epoch that was processed by a claim
     * @return the sequential number of the last claimed epoch
     */
    function _lastProcessedEpoch() internal view virtual returns (uint64);

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

    /**
     * @notice process the internal state up until the given epoch (excluded) and return the state change diff
     * @dev the internal state change between the epochs lastProcessedEpoch + 1 (included) and the currentEpoch - 1 is aggregated and returned without actually changing the state
     * The internal state has to be updated separately
     * @param rate the rate that is applied to calculate the returned amount of processed funds
     * @param upToEpoch the epoch up until to process to (excluded)
     * @return amount the amount of funds processed in the processed epochs
     * @return starting the number of subscription shares that started in the epochs processed
     * @return expiring the number of subscription shares that expired in the epochs processed
     */
    function _processEpochs(uint256 rate, uint64 upToEpoch)
        internal
        view
        virtual
        returns (uint256 amount, uint256 starting, uint256 expiring);

    /**
     * @notice updates the internal state of the subscription contract by processing completed epochs and returning the amount of newly claimable funds
     * @dev this function uses _processEpochs to get an aggregated state change and subsequently apply it to storage
     * @param rate the rate that is applied to calculate the returned amount of processed funds
     * @return The amount of claimable funds
     */
    function _handleEpochsClaim(uint256 rate) internal virtual returns (uint256);

    /**
     * @notice Adds a new subscription based on amount of funds and number of shares to the epochs
     * @dev the given rate and amount are used to calculate the duration of the subscription, the number of shares does not affect the rate or amount.
     * @param amount The amount of funds for this new subscription
     * @param shares The number of shares this new subscription contains
     * @param rate The rate that is applied to the amount
     */
    function _addNewSubscriptionToEpochs(uint256 amount, uint256 shares, uint256 rate) internal virtual;

    /**
     * @notice moves an existing, non-expired subscription in the epochs data
     * @dev the subscription is extended using the new deposit data and removed from the old deposit data location
     * @param oldDepositedAt The time the subscription was originally deposited/started at
     * @param oldDeposit The amount of funds the original subscription contained
     * @param newDepositedAt The time the subscription is now extended from (probably now)
     * @param newDeposit The amount of funds the subscription now contains
     * @param shares The number of shares this subscription contains
     * @param rate The rate that is applied to the amount
     */
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
        uint64 _epochSize;
        // the last claimed epoch
        uint64 _lastProcessedEpoch;
        // this value is set, after the initial claim.
        // It allows us to identify the meaning of epoch 0,
        // if this value is false, there was no claim at epoch 0,
        // otherwise epoch 0 is actually a valid last processed epoch
        bool _initialClaim;
        mapping(uint64 => Epoch) _epochs;
        // number of active subscriptions with a multiplier represented as shares
        // base 100:
        // 1 Sub * 1x == 100 shares
        // 1 Sub * 2.5x == 250 shares
        uint256 _activeSubShares;
        // internal counter for claimed subscription funds
        uint256 _claimed;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.Epochs")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EpochsStorageLocation = 0xa37ad06674bbaa0ce562b40a47c6d9e758dfe44c585749b25d5bb38fa0f8d500;

    function _getEpochsStorage() private pure returns (EpochsStorage storage $) {
        assembly {
            $.slot := EpochsStorageLocation
        }
    }

    function __Epochs_init(uint64 epochSize) internal onlyInitializing {
        __Epochs_init_unchained(epochSize);
    }

    function __Epochs_init_unchained(uint64 epochSize) internal onlyInitializing {
        EpochsStorage storage $ = _getEpochsStorage();
        $._epochSize = epochSize;
        $._lastProcessedEpoch = uint64((uint256(_currentEpoch())).max(1) - 1); // current epoch -1 or 0
    }

    function _epochSize() internal view override returns (uint64) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._epochSize;
    }

    function _currentEpoch() internal view override returns (uint64) {
        EpochsStorage storage $ = _getEpochsStorage();
        return _now() / $._epochSize;
    }

    function _claimed() internal view override returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._claimed;
    }

    function _lastProcessedEpoch() internal view override returns (uint64) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._lastProcessedEpoch;
    }

    function _activeSubShares() internal view override returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        uint64 currentEpoch = _currentEpoch();
        uint256 _activeSubs = $._activeSubShares;

        for (uint64 i = $._lastProcessedEpoch; i < currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs += $._epochs[i].starting;
            _activeSubs -= $._epochs[i].expiring;
        }

        // add most recent starting subs, being optimistic
        _activeSubs += $._epochs[currentEpoch].starting;
        return _activeSubs;
    }

    /**
     * @notice handle from which epoch to start processing
     * @param suggestedLastEpoch the epoch that was last processed (exclusive)
     * @param initialClaim was there an initial claim, thus was epoch 0 processed?
     * @return the epoch start from processing (inclusive)
     */
    function _startProcessingEpoch(uint64 suggestedLastEpoch, bool initialClaim) internal pure returns (uint64) {
        if (suggestedLastEpoch > 0) {
            return suggestedLastEpoch + 1;
        }
        // the given epoch is 0
        if (initialClaim) {
            // 0 + 1
            return 1;
        }
        return 0;
    }

    function _processEpochs(uint256 rate, uint64 upToEpoch)
        internal
        view
        override
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        EpochsStorage storage $ = _getEpochsStorage();
        uint256 _activeSubs = $._activeSubShares;

        for (uint64 i = _startProcessingEpoch($._lastProcessedEpoch, $._initialClaim); i < upToEpoch; i++) {
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
        uint64 currentEpoch = _currentEpoch();
        require(currentEpoch > 0, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = _processEpochs(rate, currentEpoch);

        // delete epochs
        EpochsStorage storage $ = _getEpochsStorage();
        for (uint64 i = _startProcessingEpoch($._lastProcessedEpoch, $._initialClaim); i < currentEpoch; i++) {
            delete $._epochs[i];
        }

        if (starting > expiring) {
            $._activeSubShares += starting - expiring;
        } else {
            $._activeSubShares -= expiring - starting;
        }

        $._lastProcessedEpoch = currentEpoch - 1;
        $._claimed += amount;
        $._initialClaim = true;

        return amount;
    }

    function _addNewSubscriptionToEpochs(uint256 amount, uint256 shares, uint256 rate) internal override {
        uint256 now_ = _now();
        uint256 expiresAt_ = amount.expiresAt(now_, rate);

        // starting
        uint64 currentEpoch = _currentEpoch();

        EpochsStorage storage $ = _getEpochsStorage();
        $._epochs[currentEpoch].starting += shares;
        uint256 remaining = ($._epochSize - (now_ % $._epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        );
        $._epochs[currentEpoch].partialFunds += (remaining * rate);

        // ending
        uint64 expiringEpoch = uint64(expiresAt_ / $._epochSize);
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
            require(oldExpiringAt >= now_, "Epoch: subscription is already expired");
            // update old epoch
            uint64 oldEpoch = uint64(oldExpiringAt / $._epochSize);
            $._epochs[oldEpoch].expiring -= shares;
            uint256 removable = (oldExpiringAt - uint256(((oldEpoch * $._epochSize))).max(now_)) * rate;
            $._epochs[oldEpoch].partialFunds -= removable;
        }

        // update new epoch
        uint256 newEndingBlock = newDeposit.expiresAt(newDepositedAt, rate);
        uint64 newEpoch = uint64(newEndingBlock / $._epochSize);
        $._epochs[newEpoch].expiring += shares;
        $._epochs[newEpoch].partialFunds += (newEndingBlock - uint256(((newEpoch * $._epochSize))).max(now_)) * rate;
    }
}