// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription} from "./ISubscription.sol";
import {OwnableByERC721Upgradeable} from "./OwnableByERC721Upgradeable.sol";
import {SubscriptionLib} from "./SubscriptionLib.sol";

import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract Subscription is
    ISubscription,
    ERC721Upgradeable,
    OwnableByERC721Upgradeable,
    PausableUpgradeable
{
    // should the tokenId 0 == owner?

    // TODO multiplier for Subscriptions
    // TODO instantiation with proxy
    // TODO refactor event deposited to spent amount?
    // TODO define metadata
    // TODO max supply?
    // TODO max donation / deposit
    // TODO improve active subscriptions to include current epoch changes
    // TODO interchangable implementation for time tracking: blocks vs timestamp
    // TODO retire function, sends token.balance to owner
    // TODO ownable interface?
    // TODO pausable interface?

    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using SubscriptionLib for uint256;

    struct SubscriptionData {
        uint256 mintedAt; // mint date
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 lastDepositAt; // date of last deposit
        uint256 currentDeposit; // unspent amount of tokens at lastDepositAt
        uint256 lockedAmount; // amount of funds locked
        // TODO change type
        uint256 multiplier;
    }

    struct Epoch {
        uint256 expiring; // number of expiring subscriptions
        uint256 starting; // number of starting subscriptions
        uint256 partialFunds; // the amount of funds belonging to starting and ending subs in the epoch
    }

    uint256 public constant MULTIPLIER_BASE = 100;

    uint256 public totalSupply;

    IERC20Metadata public token;

    /// @notice rate per block
    /// @dev the amount of tokens paid per block based on 18 decimals
    uint256 public rate;

    // locked % of deposited amount
    // 0 - 10000
    // TODO uint32
    uint256 public lock;
    uint256 public constant LOCK_BASE = 10_000;

    mapping(uint256 => SubscriptionData) private subData;

    // number of active subscriptions with a multiplier represented as shares
    // base 100:
    // 1 Sub * 1x == 100 shares
    // 1 Sub * 2.5x == 250 shares
    uint256 public activeSubShares;

    // time of contract's inception
    // uint private creationBlock;
    uint256 private epochSize;

    uint256 private _lastProcessedEpoch;

    // external amount
    uint256 public totalClaimed;

    mapping(uint256 => Epoch) private epochs;

    modifier requireExists(uint256 tokenId) {
        require(_exists(tokenId), "SUB: subscription does not exist");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20Metadata _token,
        uint256 _rate,
        uint256 _lock,
        uint256 _epochSize,
        address creatorContract,
        uint256 creatorTokenId
    ) external initializer {
        // owner is set to msg.sender
        require(_epochSize > 0, "SUB: invalid epochSize");
        require(
            address(_token) != address(0),
            "SUB: token cannot be 0 address"
        );
        require(_lock <= 10_000, "SUB: lock percentage out of range");
        require(_rate > 0, "SUB: rate cannot be 0");
        require(creatorContract != address(0), "SUB: creator address not set");

        // call initializers of inherited contracts
        // TODO set metadata
        __ERC721_init_unchained("Subscription", "SUB");
        __OwnableByERC721_init_unchained(creatorContract, creatorTokenId);
        __Pausable_init_unchained();

        token = _token;
        rate = _rate;
        lock = _lock;
        epochSize = _epochSize;

        _lastProcessedEpoch = getCurrentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    function getCurrentEpoch() internal view returns (uint256) {
        return block.number / epochSize;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice "Mints" a new subscription token
    function mint(
        uint256 amount,
        uint256 multiplier,
        string calldata message
    ) external whenNotPaused returns (uint256) {
        // multiplier must be larger that 1x and less than 1000x
        // TODO in one call
        require(
            multiplier >= 100 && multiplier <= 100_000,
            "SUB: multiplier invalid"
        );
        // TODO check minimum amount?
        // TODO handle 0 amount mints -> skip parts of code, new event type
        // uint subscriptionEnd = amount / rate;
        uint256 tokenId = ++totalSupply;
        uint256 mRate = (rate * multiplier) / MULTIPLIER_BASE;

        uint256 internalAmount = amount.toInternal(token).adjustToRate(mRate);

        subData[tokenId].mintedAt = block.number;
        subData[tokenId].lastDepositAt = block.number;
        subData[tokenId].totalDeposited = internalAmount;
        subData[tokenId].currentDeposit = internalAmount;
        subData[tokenId].multiplier = multiplier;

        // set lockedAmount
        subData[tokenId].lockedAmount = ((internalAmount * lock) / LOCK_BASE)
            .adjustToRate(mRate);

        addNewSubscriptionToEpochs(internalAmount, multiplier);

        // we transfer the ORIGINAL amount into the contract, claiming any overflows
        token.safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        emit SubscriptionRenewed(
            tokenId,
            amount,
            internalAmount,
            msg.sender,
            message
        );

        return tokenId;
    }

    function addNewSubscriptionToEpochs(uint256 amount, uint256 multiplier)
        internal
    {
        uint256 mRate = (rate * multiplier) / MULTIPLIER_BASE;
        uint256 expiresAt_ = block.number + (amount / mRate);

        // TODO use _expiresAt(tokenId)
        // starting
        uint256 _currentEpoch = getCurrentEpoch();
        epochs[_currentEpoch].starting += multiplier;
        uint256 remaining = (epochSize - (block.number % epochSize)).min(
            expiresAt_ - block.number // subscription ends within current block
        );
        epochs[_currentEpoch].partialFunds += (remaining * mRate);

        // ending
        uint256 expiringEpoch = expiresAt_ / epochSize;
        epochs[expiringEpoch].expiring += multiplier;
        epochs[expiringEpoch].partialFunds +=
            (expiresAt_ - (expiringEpoch * epochSize)).min(
                expiresAt_ - block.number // subscription ends within current block
            ) *
            mRate;
    }

    function moveSubscriptionInEpochs(
        uint256 _lastDepositAt,
        uint256 _oldDeposit,
        uint256 _newDeposit,
        uint256 multiplier
    ) internal {
        uint256 mRate = (rate * multiplier) / MULTIPLIER_BASE;
        // when does the sub currently end?
        uint256 oldExpiringAt = _lastDepositAt + (_oldDeposit / mRate);
        // update old epoch
        uint256 oldEpoch = oldExpiringAt / epochSize;
        epochs[oldEpoch].expiring -= multiplier;
        uint256 removable = (oldExpiringAt -
            ((oldEpoch * epochSize).max(block.number))) * mRate;
        epochs[oldEpoch].partialFunds -= removable;

        // update new epoch
        uint256 newEndingBlock = _lastDepositAt + (_newDeposit / mRate);
        uint256 newEpoch = newEndingBlock / epochSize;
        epochs[newEpoch].expiring += multiplier;
        epochs[newEpoch].partialFunds +=
            (newEndingBlock - ((newEpoch * epochSize).max(block.number))) *
            mRate;
    }

    /// @notice adds deposits to an existing subscription token
    function renew(
        uint256 tokenId,
        uint256 amount,
        string calldata message
    ) external whenNotPaused requireExists(tokenId) {
        uint256 multiplier = subData[tokenId].multiplier;
        uint256 mRate = (rate * multiplier) / MULTIPLIER_BASE;
        uint256 internalAmount = amount.toInternal(token).adjustToRate(mRate);
        require(internalAmount >= mRate, "SUB: amount too small");

        uint256 oldExpiresAt = _expiresAt(tokenId);

        uint256 remainingDeposit = 0;
        if (oldExpiresAt > block.number) {
            // subscription is still active
            remainingDeposit = (oldExpiresAt - block.number) * mRate;

            uint256 _currentDeposit = subData[tokenId].currentDeposit;
            uint256 newDeposit = _currentDeposit + internalAmount;
            moveSubscriptionInEpochs(
                subData[tokenId].lastDepositAt,
                _currentDeposit,
                newDeposit,
                multiplier
            );
        } else {
            // subscription is inactive
            addNewSubscriptionToEpochs(internalAmount, multiplier);
        }

        uint256 deposit = remainingDeposit + internalAmount;
        subData[tokenId].currentDeposit = deposit;
        subData[tokenId].lastDepositAt = block.number;
        subData[tokenId].totalDeposited += internalAmount;
        subData[tokenId].lockedAmount = ((deposit * lock) / LOCK_BASE)
            .adjustToRate(mRate);

        // finally transfer tokens into this contract
        // we use the ORIGINAL amount here
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(
            tokenId,
            amount,
            subData[tokenId].totalDeposited, // TODO use extra var?
            msg.sender,
            message
        );
    }

    function withdraw(uint256 tokenId, uint256 amount)
        external
        requireExists(tokenId)
    {
        _withdraw(tokenId, amount.toInternal(token));
    }

    function cancel(uint256 tokenId) external requireExists(tokenId) {
        _withdraw(tokenId, _withdrawable(tokenId));
    }

    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(msg.sender == ownerOf(tokenId), "SUB: not the owner");

        uint256 withdrawable_ = _withdrawable(tokenId);
        require(amount <= withdrawable_, "SUB: amount exceeds withdrawable");

        uint256 _currentDeposit = subData[tokenId].currentDeposit;
        uint256 _lastDepositAt = subData[tokenId].lastDepositAt;

        uint256 newDeposit = _currentDeposit - amount;
        moveSubscriptionInEpochs(
            _lastDepositAt,
            _currentDeposit,
            newDeposit,
            subData[tokenId].multiplier
        );

        // when is is the sub going to end now?
        subData[tokenId].currentDeposit = newDeposit;
        subData[tokenId].totalDeposited -= amount;

        uint256 externalAmount = amount.toExternal(token);
        token.safeTransfer(msg.sender, externalAmount);

        emit SubscriptionWithdrawn(
            tokenId,
            externalAmount,
            subData[tokenId].totalDeposited
        );
    }

    function isActive(uint256 tokenId)
        external
        view
        requireExists(tokenId)
        returns (bool)
    {
        return _isActive(tokenId);
    }

    function _isActive(uint256 tokenId) private view returns (bool) {
        // a subscription is active form the starting block (including)
        // to the calculated end block (excluding)
        // active = [start, + deposit / rate)
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 mRate = (rate * subData[tokenId].multiplier) / MULTIPLIER_BASE;

        uint256 end = lastDeposit + (currentDeposit_ / mRate);

        return block.number < end;
    }

    function deposited(uint256 tokenId)
        external
        view
        requireExists(tokenId)
        returns (uint256)
    {
        // TODO is this the correct implementation?
        return subData[tokenId].totalDeposited.toExternal(token);
    }

    function expiresAt(uint256 tokenId)
        external
        view
        requireExists(tokenId)
        returns (uint256)
    {
        return _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view returns (uint256) {
        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        uint256 mRate = (rate * subData[tokenId].multiplier) / MULTIPLIER_BASE;
        return lastDeposit + (currentDeposit_ / mRate);
    }

    function withdrawable(uint256 tokenId)
        external
        view
        requireExists(tokenId)
        returns (uint256)
    {
        return _withdrawable(tokenId).toExternal(token);
    }

    function _withdrawable(uint256 tokenId) private view returns (uint256) {
        if (!_isActive(tokenId)) {
            return 0;
        }

        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        uint256 lockedAmount = subData[tokenId].lockedAmount;
        uint256 mRate = (rate * subData[tokenId].multiplier) / MULTIPLIER_BASE;
        uint256 usedBlocks = block.number - lastDeposit;

        return
            (currentDeposit_ - lockedAmount).min(
                currentDeposit_ - (usedBlocks * mRate)
            );
    }

    function spent(uint256 tokenId)
        external
        view
        requireExists(tokenId)
        returns (uint256)
    {
        uint256 totalDeposited = subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!_isActive(tokenId)) {
            spentAmount = totalDeposited;
        } else {
            uint256 mRate = (rate * subData[tokenId].multiplier) /
                MULTIPLIER_BASE;
            spentAmount =
                totalDeposited -
                subData[tokenId].currentDeposit +
                ((block.number - subData[tokenId].lastDepositAt) * mRate);
        }

        return spentAmount.toExternal(token);
    }

    function tip(
        uint256 tokenId,
        uint256 amount,
        string calldata message
    ) external requireExists(tokenId) {
        require(amount > 0, "SUB: amount too small");

        subData[tokenId].totalDeposited += amount.toInternal(token);

        token.safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(
            tokenId,
            amount,
            subData[tokenId].totalDeposited, // TODO create extra var?
            _msgSender(),
            message
        );
    }

    /// @notice The owner claims their rewards
    function claim() external onlyOwner {
        require(getCurrentEpoch() > 1, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = processEpochs();

        // delete epochs
        uint256 _currentEpoch = getCurrentEpoch();

        // TODO: copy processEpochs function body to decrease gas?
        for (uint256 i = lastProcessedEpoch(); i < _currentEpoch; i++) {
            delete epochs[i];
        }

        if (starting > expiring) {
            activeSubShares += starting - expiring;
        } else {
            activeSubShares -= expiring - starting;
        }

        _lastProcessedEpoch = _currentEpoch - 1;

        // convert to external amount
        amount = amount.toExternal(token);
        totalClaimed += amount;

        token.safeTransfer(ownerAddress(), amount);

        emit FundsClaimed(amount, totalClaimed);
    }

    function claimable() external view returns (uint256) {
        (uint256 amount, , ) = processEpochs();

        // TODO when optimizing, define var name in signature
        return amount.toExternal(token);
    }

    function lastProcessedEpoch() private view returns (uint256 i) {
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        if (0 == _lastProcessedEpoch && getCurrentEpoch() > 1) {
            i = 0;
        } else {
            i = _lastProcessedEpoch + 1;
        }
    }

    function processEpochs()
        internal
        view
        returns (
            uint256 amount,
            uint256 starting,
            uint256 expiring
        )
    {
        uint256 _currentEpoch = getCurrentEpoch();
        uint256 _activeSubs = activeSubShares;

        for (uint256 i = lastProcessedEpoch(); i < _currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= epochs[i].expiring;

            // we do not apply the individual multiplier to `rate` as it is
            // included in _activeSubs, expiring, and starting subs
            amount +=
                epochs[i].partialFunds +
                (_activeSubs * epochSize * rate) /
                MULTIPLIER_BASE;
            starting += epochs[i].starting;
            expiring += epochs[i].expiring;

            // add new subs starting in this epoch
            _activeSubs += epochs[i].starting;
        }
    }
}
