// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription, Metadata, SubSettings, SubscriptionFlags} from "./ISubscription.sol";
import {OwnableByERC721Upgradeable} from "../OwnableByERC721Upgradeable.sol";
import {SubscriptionLib} from "./SubscriptionLib.sol";
import {SubscriptionViewLib} from "./SubscriptionViewLib.sol";

import {TimeAware} from "./TimeAware.sol";
import {Epochs} from "./Epochs.sol";
import {SubscriptionDataHandling} from "./SubscriptionDataHandling.sol";

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
    TimeAware,
    Epochs,
    SubscriptionDataHandling,
    ERC721EnumerableUpgradeable,
    OwnableByERC721Upgradeable,
    SubscriptionFlags,
    FlagSettings
{
    // should the tokenId 0 == owner?

    // TODO merge: seperate funds that are accumulated in the current sub and funds merged in, enable via flag
    // TODO "upgrade"/migrate to other subscription: separate migrated funds from accumulated ones, enable via flag
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
    // TODO add royalties?

    // TODO add natspec comments

    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using SubscriptionLib for uint256;
    using Strings for uint256;
    using Strings for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    using SubscriptionViewLib for Subscription;

    Metadata public metadata;
    SubSettings public settings;

    // TODO replace me?
    CountersUpgradeable.Counter private _tokenIdTracker;

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
        __Epochs_init_unchained(_settings.epochSize);
        __SubscriptionCore_init_unchained(_settings.rate);
        __SubscriptionDataHandling_init_unchained(_settings.lock);

        metadata = _metadata;
        settings = _settings;

        // TODO check validity of token
    }

    function contractURI() external view returns (string memory) {
        return this.contractData();
    }

    function activeSubShares() external view returns (uint256) {
        return _getActiveSubShares();
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

    function setFlags(uint256 flags) external onlyOwnerOrApproved requireValidFlags(flags) {
        _setFlags(flags);
    }

    function unsetFlags(uint256 flags) external onlyOwnerOrApproved requireValidFlags(flags) {
        _unsetFlags(flags);
    }

    function setDescription(string calldata _description) external onlyOwnerOrApproved {
        metadata.description = _description;
    }

    function setImage(string calldata _image) external onlyOwnerOrApproved {
        metadata.image = _image;
    }

    function setExternalUrl(string calldata _externalUrl) external onlyOwnerOrApproved {
        metadata.externalUrl = _externalUrl;
    }

    function burn(uint256 tokenId) external {
        // only owner of tokenId can burn
        require(msg.sender == ownerOf(tokenId), "SUB: not the owner");

        _deleteSubscription(tokenId);

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

        _createSubscription(tokenId, internalAmount, multiplier);

        // TODO now and mRate need rework
        uint256 now_ = _now();
        addNewSubscriptionToEpochs(internalAmount, multiplier, mRate, now_);

        // we transfer the ORIGINAL amount into the contract, claiming any overflows
        settings.token.safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        emit SubscriptionRenewed(tokenId, amount, internalAmount, msg.sender, message);

        return tokenId;
    }

    /// @notice adds deposits to an existing subscription token
    function renew(uint256 tokenId, uint256 amount, string calldata message)
        external
        whenDisabled(RENEWAL_PAUSED)
        requireExists(tokenId)
    {
        uint256 now_ = _now();
        uint256 multiplier = _multiplier(tokenId);
        uint256 mRate = multipliedRate(multiplier);
        uint256 internalAmount = amount.toInternal(settings.token).adjustToRate(mRate);
        require(internalAmount >= mRate, "SUB: amount too small");

        {
            (uint256 oldDeposit, uint256 newDeposit, bool reactived, uint256 lastDepositedAt) =
                _addToSubscription(tokenId, internalAmount);

            if (reactived) {
                // subscription was inactive
                addNewSubscriptionToEpochs(newDeposit, multiplier, mRate, now_);
            } else {
                moveSubscriptionInEpochs(lastDepositedAt, oldDeposit, now_, newDeposit, multiplier, mRate);
            }
        }

        // finally transfer tokens into this contract
        // we use the ORIGINAL amount here
        settings.token.safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(tokenId, amount, _totalDeposited(tokenId), msg.sender, message);
        emit MetadataUpdate(tokenId);
    }

    function withdraw(uint256 tokenId, uint256 amount) external requireExists(tokenId) {
        _withdraw(tokenId, amount.toInternal(settings.token));
    }

    function cancel(uint256 tokenId) external requireExists(tokenId) {
        _withdraw(tokenId, _withdrawableFromSubscription(tokenId));
    }

    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        // TODO move to withdraw
        uint256 withdrawable_ = _withdrawableFromSubscription(tokenId);
        require(amount <= withdrawable_, "SUB: amount exceeds withdrawable");


        uint256 _lastDepositAt = _lastDepositedAt(tokenId);
        (uint256 oldDeposit, uint256 newDeposit) = _withdrawFromSubscription(tokenId, amount);

        uint256 multiplier = _multiplier(tokenId);
        moveSubscriptionInEpochs(
            _lastDepositAt,
            oldDeposit,
            _lastDepositAt,
            newDeposit,
            multiplier,
            // TODO weird?
            multipliedRate(multiplier)
        );

        uint256 externalAmount = amount.toExternal(settings.token);
        settings.token.safeTransfer(_msgSender(), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, _totalDeposited(tokenId));
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function deposited(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _totalDeposited(tokenId).toExternal(settings.token);
    }

    function expiresAt(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _expiresAt(tokenId);
    }

    function withdrawable(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _withdrawableFromSubscription(tokenId).toExternal(settings.token);
    }

    function spent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (uint256 spentAmount,) = _spent(tokenId);
        return spentAmount.toExternal(settings.token);
    }

    function unspent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (, uint256 unspentAmount) = _spent(tokenId);
        return unspentAmount.toExternal(settings.token);
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        _incrementTotalDeposited(tokenId, amount.toInternal(settings.token));

        settings.token.safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(tokenId, amount, _totalDeposited(tokenId), _msgSender(), message);
        emit MetadataUpdate(tokenId);
    }

    /// @notice The owner claims their rewards
    function claim(address to) external onlyOwnerOrApproved {
        uint256 amount = handleEpochsClaim(settings.rate);

        // convert to external amount
        amount = amount.toExternal(settings.token);
        totalClaimed += amount;

        settings.token.safeTransfer(to, amount);

        emit FundsClaimed(amount, totalClaimed);
    }

    function claimable() public view returns (uint256) {
        (uint256 amount,,) = processEpochs(settings.rate, _getCurrentEpoch());

        return amount.toExternal(settings.token);
    }
}
