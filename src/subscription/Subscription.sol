// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription, Metadata, SubSettings, SubscriptionFlags} from "./ISubscription.sol";
import {OwnableByERC721Upgradeable} from "../OwnableByERC721Upgradeable.sol";
import {SubscriptionLib} from "./SubscriptionLib.sol";
import {SubscriptionViewLib} from "./SubscriptionViewLib.sol";

import {FlagSettings} from "../FlagSettings.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC165Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";
import {IERC721MetadataUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";

import {CountersUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/CountersUpgradeable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

abstract contract Subscription is
    ISubscription,
    ERC721EnumerableUpgradeable,
    OwnableByERC721Upgradeable,
    SubscriptionFlags,
    FlagSettings
{
    // should the tokenId 0 == owner?

    // TODO max donation / deposit
    // TODO allow 0 amount tip or check for a configurable min tip amount?
    // TODO refactor event deposited to spent amount?
    // TODO define metadata
    // TODO upgrade function / flow, migrating one token into another
    // TODO fast block time + small epoch size => out of gas?
    // TODO split owner and user sides into separate abstract contracts?
    //      use structs to combine fields/members?
    // TODO optimize variable sizes
    //      add gaps
    // TODO instead of multiple instances have everything in 1 ERC721 instance?
    // TODO generate simple image on chain to illustrate sub status

    // TODO add natspec comments

    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using SubscriptionLib for uint256;
    using Strings for uint256;
    using Strings for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    using SubscriptionViewLib for Subscription;

    struct SubscriptionData {
        uint256 mintedAt; // mint date
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 lastDepositAt; // date of last deposit
        uint256 currentDeposit; // unspent amount of tokens at lastDepositAt
        uint256 lockedAmount; // amount of funds locked
        // TODO change type
        uint256 multiplier;
    }

    // epochs always start from genesis
    struct Epoch {
        uint256 expiring; // number of expiring subscriptions
        uint256 starting; // number of starting subscriptions
        uint256 partialFunds; // the amount of funds belonging to starting and ending subs in the epoch
    }

    uint256 public constant MULTIPLIER_BASE = 100;
    uint256 public constant LOCK_BASE = 10_000;

    Metadata public metadata;
    SubSettings public settings;

    mapping(uint256 => SubscriptionData) internal subData;
    mapping(uint256 => Epoch) private epochs;

    // TODO replace me?
    CountersUpgradeable.Counter private _tokenIdTracker;

    // number of active subscriptions with a multiplier represented as shares
    // base 100:
    // 1 Sub * 1x == 100 shares
    // 1 Sub * 2.5x == 250 shares
    uint256 public activeSubShares;

    uint256 private _lastProcessedEpoch;

    // external amount
    uint256 public totalClaimed;

    modifier requireExists(uint256 tokenId) {
        require(_exists(tokenId), "SUB: subscription does not exist");
        _;
    }

    modifier requireValidFlags(uint256 flags) {
        require(flags > 0, "SUB: invalid settings");
        require(flags <= ALL_FLAGS, "SUB: invalid settings");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        Metadata calldata _metadata,
        SubSettings calldata _settings,
        address profileContract,
        uint256 profileTokenId
    ) external initializer {
        require(_settings.epochSize > 0, "SUB: invalid epochSize");
        require(address(_settings.token) != address(0), "SUB: token cannot be 0 address");
        require(_settings.lock <= 10_000, "SUB: lock percentage out of range");
        require(_settings.rate > 0, "SUB: rate cannot be 0");
        // check that profileContract is a contract of ERC721 and does have a tokenId
        require(profileContract != address(0), "SUB: profile address not set");

        // call initializers of inherited contracts
        // TODO set metadata
        __ERC721_init_unchained(tokenName, tokenSymbol);
        __OwnableByERC721_init_unchained(profileContract, profileTokenId);
        __FlagSettings_init_unchained();

        metadata = _metadata;
        settings = _settings;

        // TODO check validity of token

        _lastProcessedEpoch = _getCurrentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    function _now() internal view virtual returns (uint256);

    function contractURI() external view returns (string memory) {
        return this.contractData();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC721MetadataUpgradeable)
        returns (string memory)
    {
        _requireMinted(tokenId);

        return this.tokenData(tokenId);
    }

    // TODO rename, add leading underscore due to being an internal func
    function _getCurrentEpoch() internal view returns (uint256) {
        return _now() / settings.epochSize;
    }

    function setFlags(uint256 flags) external onlyOwner requireValidFlags(flags) {
        _setFlags(flags);
    }

    function unsetFlags(uint256 flags) external onlyOwner requireValidFlags(flags) {
        _unsetFlags(flags);
    }

    function setDescription(string calldata _description) external onlyOwner {
        metadata.description = _description;
    }

    function setImage(string calldata _image) external onlyOwner {
        metadata.image = _image;
    }

    function setExternalUrl(string calldata _externalUrl) external onlyOwner {
        metadata.externalUrl = _externalUrl;
    }

    function multipliedRate(uint256 multiplier) internal view returns (uint256) {
        return (settings.rate * multiplier) / MULTIPLIER_BASE;
    }

    function burn(uint256 tokenId) external {
        // only owner of tokenId can burn
        require(msg.sender == ownerOf(tokenId), "SUB: not the owner");

        delete subData[tokenId];

        _burn(tokenId);
    }

    /// @notice "Mints" a new subscription token
    function mint(uint256 amount, uint256 multiplier, string calldata message)
        external
        whenDisabled(MINTING_PAUSED)
        returns (uint256)
    {
        // check max supply
        require(totalSupply() < settings.maxSupply, "SUB: max supply reached");
        // multiplier must be larger that 1x and less than 1000x
        // TODO in one call
        require(multiplier >= 100 && multiplier <= 100_000, "SUB: multiplier invalid");
        // TODO check minimum amount?
        // TODO handle 0 amount mints -> skip parts of code, new event type
        // uint subscriptionEnd = amount / rate;
        _tokenIdTracker.increment();
        uint256 tokenId = _tokenIdTracker.current();
        uint256 mRate = multipliedRate(multiplier);

        uint256 internalAmount = amount.toInternal(settings.token).adjustToRate(mRate);

        uint256 now_ = _now();
        subData[tokenId].mintedAt = now_;
        subData[tokenId].lastDepositAt = now_;
        subData[tokenId].totalDeposited = internalAmount;
        subData[tokenId].currentDeposit = internalAmount;
        subData[tokenId].multiplier = multiplier;

        // set lockedAmount
        subData[tokenId].lockedAmount = ((internalAmount * settings.lock) / LOCK_BASE).adjustToRate(mRate);

        addNewSubscriptionToEpochs(internalAmount, multiplier);

        // we transfer the ORIGINAL amount into the contract, claiming any overflows
        settings.token.safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        emit SubscriptionRenewed(tokenId, amount, internalAmount, msg.sender, message);

        return tokenId;
    }

    function addNewSubscriptionToEpochs(uint256 amount, uint256 multiplier) internal {
        uint256 now_ = _now();
        uint256 mRate = multipliedRate(multiplier);
        uint256 expiresAt_ = _expiresAt(now_, amount, mRate);

        // starting
        uint256 _currentEpoch = _getCurrentEpoch();
        epochs[_currentEpoch].starting += multiplier;
        uint256 remaining = (settings.epochSize - (now_ % settings.epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        );
        epochs[_currentEpoch].partialFunds += (remaining * mRate);

        // ending
        uint256 expiringEpoch = expiresAt_ / settings.epochSize;
        epochs[expiringEpoch].expiring += multiplier;
        epochs[expiringEpoch].partialFunds += (expiresAt_ - (expiringEpoch * settings.epochSize)).min(
            expiresAt_ - now_ // subscription ends within the current time slot
        ) * mRate;
    }

    function moveSubscriptionInEpochs(
        uint256 _lastDepositAt,
        uint256 _oldDeposit,
        uint256 _newDeposit,
        uint256 multiplier
    ) internal {
        uint256 now_ = _now();
        uint256 mRate = multipliedRate(multiplier);
        // when does the sub currently end?
        uint256 oldExpiringAt = _expiresAt(_lastDepositAt, _oldDeposit, mRate);
        // update old epoch
        uint256 oldEpoch = oldExpiringAt / settings.epochSize;
        epochs[oldEpoch].expiring -= multiplier;
        uint256 removable = (oldExpiringAt - ((oldEpoch * settings.epochSize).max(now_))) * mRate;
        epochs[oldEpoch].partialFunds -= removable;

        // update new epoch
        uint256 newEndingBlock = _expiresAt(_lastDepositAt, _newDeposit, mRate);
        uint256 newEpoch = newEndingBlock / settings.epochSize;
        epochs[newEpoch].expiring += multiplier;
        epochs[newEpoch].partialFunds += (newEndingBlock - ((newEpoch * settings.epochSize).max(now_))) * mRate;
    }

    /// @notice adds deposits to an existing subscription token
    function renew(uint256 tokenId, uint256 amount, string calldata message)
        external
        whenDisabled(RENEWAL_PAUSED)
        requireExists(tokenId)
    {
        uint256 now_ = _now();
        uint256 multiplier = subData[tokenId].multiplier;
        uint256 mRate = multipliedRate(multiplier);
        uint256 internalAmount = amount.toInternal(settings.token).adjustToRate(mRate);
        require(internalAmount >= mRate, "SUB: amount too small");

        uint256 remainingDeposit = 0;
        {
            uint256 oldExpiresAt = _expiresAt(tokenId);
            if (oldExpiresAt > now_) {
                // subscription is still active
                remainingDeposit = (oldExpiresAt - now_) * mRate;

                uint256 _currentDeposit = subData[tokenId].currentDeposit;
                moveSubscriptionInEpochs(
                    subData[tokenId].lastDepositAt, _currentDeposit, _currentDeposit + internalAmount, multiplier
                );
            } else {
                // subscription is inactive
                addNewSubscriptionToEpochs(internalAmount, multiplier);
            }
        }

        uint256 deposit = remainingDeposit + internalAmount;
        subData[tokenId].currentDeposit = deposit;
        subData[tokenId].lastDepositAt = now_;
        subData[tokenId].totalDeposited += internalAmount;
        subData[tokenId].lockedAmount = ((deposit * settings.lock) / LOCK_BASE).adjustToRate(mRate);

        // finally transfer tokens into this contract
        // we use the ORIGINAL amount here
        settings.token.safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(
            tokenId,
            amount,
            subData[tokenId].totalDeposited, // TODO use extra var?
            msg.sender,
            message
        );
        emit MetadataUpdate(tokenId);
    }

    function withdraw(uint256 tokenId, uint256 amount) external requireExists(tokenId) {
        _withdraw(tokenId, amount.toInternal(settings.token));
    }

    function cancel(uint256 tokenId) external requireExists(tokenId) {
        _withdraw(tokenId, _withdrawable(tokenId));
    }

    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        uint256 withdrawable_ = _withdrawable(tokenId);
        require(amount <= withdrawable_, "SUB: amount exceeds withdrawable");

        uint256 _currentDeposit = subData[tokenId].currentDeposit;
        uint256 _lastDepositAt = subData[tokenId].lastDepositAt;

        uint256 newDeposit = _currentDeposit - amount;
        moveSubscriptionInEpochs(_lastDepositAt, _currentDeposit, newDeposit, subData[tokenId].multiplier);

        // when is is the sub going to end now?
        subData[tokenId].currentDeposit = newDeposit;
        subData[tokenId].totalDeposited -= amount;

        uint256 externalAmount = amount.toExternal(settings.token);
        settings.token.safeTransfer(_msgSender(), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, subData[tokenId].totalDeposited);
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function _isActive(uint256 tokenId) private view returns (bool) {
        return _now() < _expiresAt(tokenId);
    }

    function deposited(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return subData[tokenId].totalDeposited.toExternal(settings.token);
    }

    function expiresAt(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view returns (uint256) {
        // a subscription is active form the starting time slot (including)
        // to the calculated ending time slot (excluding)
        // active = [start, + deposit / rate)
        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        return _expiresAt(lastDeposit, currentDeposit_, multipliedRate(subData[tokenId].multiplier));
    }

    function _expiresAt(uint256 depositedAt, uint256 amount, uint256 mRate) internal pure returns (uint256) {
        return depositedAt + (amount / mRate);
    }

    function withdrawable(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _withdrawable(tokenId).toExternal(settings.token);
    }

    function _withdrawable(uint256 tokenId) private view returns (uint256) {
        if (!_isActive(tokenId)) {
            return 0;
        }

        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        uint256 lockedAmount = subData[tokenId].lockedAmount;
        uint256 mRate = multipliedRate(subData[tokenId].multiplier);
        uint256 usedBlocks = _now() - lastDeposit;

        return (currentDeposit_ - lockedAmount).min(currentDeposit_ - (usedBlocks * mRate));
    }

    function _spent(uint256 tokenId) internal view returns (uint256, uint256) {
        uint256 totalDeposited = subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!_isActive(tokenId)) {
            spentAmount = totalDeposited;
        } else {
            spentAmount = totalDeposited - subData[tokenId].currentDeposit
                + ((_now() - subData[tokenId].lastDepositAt) * multipliedRate(subData[tokenId].multiplier));
        }

        uint256 unspentAmount = totalDeposited - spentAmount;

        return (spentAmount.toExternal(settings.token), unspentAmount.toExternal(settings.token));
    }

    function spent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (uint256 spentAmount,) = _spent(tokenId);
        return spentAmount;
    }

    function unspent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (, uint256 unspentAmount) = _spent(tokenId);
        return unspentAmount;
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        subData[tokenId].totalDeposited += amount.toInternal(settings.token);

        settings.token.safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(
            tokenId,
            amount,
            subData[tokenId].totalDeposited, // TODO create extra var?
            _msgSender(),
            message
        );
        emit MetadataUpdate(tokenId);
    }

    /// @notice The owner claims their rewards
    function claim() external onlyOwner {
        require(_getCurrentEpoch() > 1, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = processEpochs();

        // delete epochs
        uint256 _currentEpoch = _getCurrentEpoch();

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
        amount = amount.toExternal(settings.token);
        totalClaimed += amount;

        settings.token.safeTransfer(_msgSender(), amount);

        emit FundsClaimed(amount, totalClaimed);
    }

    function claimable() public view returns (uint256) {
        (uint256 amount,,) = processEpochs();

        return amount.toExternal(settings.token);
    }

    function lastProcessedEpoch() private view returns (uint256 i) {
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        if (0 == _lastProcessedEpoch && _getCurrentEpoch() > 1) {
            i = 0;
        } else {
            i = _lastProcessedEpoch + 1;
        }
    }

    function processEpochs() internal view returns (uint256 amount, uint256 starting, uint256 expiring) {
        uint256 _currentEpoch = _getCurrentEpoch();
        uint256 _activeSubs = activeSubShares;

        for (uint256 i = lastProcessedEpoch(); i < _currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= epochs[i].expiring;

            // we do not apply the individual multiplier to `rate` as it is
            // included in _activeSubs, expiring, and starting subs
            amount += epochs[i].partialFunds + (_activeSubs * settings.epochSize * settings.rate) / MULTIPLIER_BASE;
            starting += epochs[i].starting;
            expiring += epochs[i].expiring;

            // add new subs starting in this epoch
            _activeSubs += epochs[i].starting;
        }
    }
}
