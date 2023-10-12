// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription, Metadata, SubSettings, SubscriptionFlags} from "./ISubscription.sol";
import {OwnableByERC721Upgradeable} from "../OwnableByERC721Upgradeable.sol";
import {SubscriptionLib} from "./SubscriptionLib.sol";
import {SubscriptionViewLib} from "./SubscriptionViewLib.sol";

import {TimeAware} from "./TimeAware.sol";
import {Epochs} from "./Epochs.sol";
import {Rate} from "./Rate.sol";
import {SubscriptionData} from "./SubscriptionData.sol";

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
    Rate,
    Epochs,
    SubscriptionData,
    ERC721EnumerableUpgradeable,
    OwnableByERC721Upgradeable,
    SubscriptionFlags,
    FlagSettings
{
    // should the tokenId 0 == owner?

    // TODO merge: separate funds that are accumulated in the current sub and funds merged in, enable via flag
    // TODO separate sub deposits, tips, and maybe merged funds
    // TODO refactor token handling and internal/external representation to separate contract
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

    // TODO replace me?
    CountersUpgradeable.Counter private _tokenIdTracker;

    IERC20Metadata public paymentToken;
    uint256 public maxSupply;

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
        __Rate_init_unchained(_settings.rate);
        __Epochs_init_unchained(_settings.epochSize);
        __SubscriptionData_init_unchained(_settings.lock);

        paymentToken = _settings.token;
        maxSupply = _settings.maxSupply;

        metadata = _metadata;

        // TODO check validity of token
    }

    function settings() external view returns (IERC20Metadata token, uint256 rate, uint256 lock, uint256 epochSize, uint256 maxSupply) {
      token = paymentToken;
      rate = _rate();
      lock = _lock();
      epochSize = _epochSize();
      maxSupply = this.maxSupply();
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
        require(totalSupply() < maxSupply, "SUB: max supply reached");
        // multiplier must be larger that 1x and less than 1000x
        // TODO in one call
        require(multiplier >= 100 && multiplier <= 100_000, "SUB: multiplier invalid");
        // TODO check minimum amount?
        // TODO handle 0 amount mints -> skip parts of code, new event type
        // uint subscriptionEnd = amount / rate;
        _tokenIdTracker.increment();
        uint256 tokenId = _tokenIdTracker.current();
        uint256 mRate = _multipliedRate(multiplier);

        uint256 internalAmount = amount.toInternal(paymentToken).adjustToRate(mRate);

        _createSubscription(tokenId, internalAmount, multiplier);

        _addNewSubscriptionToEpochs(internalAmount, multiplier, mRate);

        // we transfer the ORIGINAL amount into the contract, claiming any overflows
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

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
        uint256 multiplier = _multiplier(tokenId);
        uint256 mRate = _multipliedRate(multiplier);
        uint256 internalAmount = amount.toInternal(paymentToken).adjustToRate(mRate);
        require(internalAmount >= mRate, "SUB: amount too small");

        {
            (uint256 oldDeposit, uint256 newDeposit, bool reactived, uint256 lastDepositedAt) =
                _addToSubscription(tokenId, internalAmount);

            if (reactived) {
                // subscription was inactive
                _addNewSubscriptionToEpochs(newDeposit, multiplier, mRate);
            } else {
                _moveSubscriptionInEpochs(lastDepositedAt, oldDeposit, _now(), newDeposit, multiplier, mRate);
            }
        }

        // finally transfer tokens into this contract
        // we use the ORIGINAL amount here
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(tokenId, amount, _totalDeposited(tokenId), msg.sender, message);
        emit MetadataUpdate(tokenId);
    }

    function withdraw(uint256 tokenId, uint256 amount) external requireExists(tokenId) {
        _withdraw(tokenId, amount.toInternal(paymentToken));
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
        _moveSubscriptionInEpochs(
            _lastDepositAt,
            oldDeposit,
            _lastDepositAt,
            newDeposit,
            multiplier,
            // TODO weird?
            _multipliedRate(multiplier)
        );

        uint256 externalAmount = amount.toExternal(paymentToken);
        paymentToken.safeTransfer(_msgSender(), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, _totalDeposited(tokenId));
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function deposited(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _totalDeposited(tokenId).toExternal(paymentToken);
    }

    function expiresAt(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _expiresAt(tokenId);
    }

    function withdrawable(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _withdrawableFromSubscription(tokenId).toExternal(paymentToken);
    }

    function spent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (uint256 spentAmount,) = _spent(tokenId);
        return spentAmount.toExternal(paymentToken);
    }

    function unspent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (, uint256 unspentAmount) = _spent(tokenId);
        return unspentAmount.toExternal(paymentToken);
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        _incrementTotalDeposited(tokenId, amount.toInternal(paymentToken));

        paymentToken.safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(tokenId, amount, _totalDeposited(tokenId), _msgSender(), message);
        emit MetadataUpdate(tokenId);
    }

    /// @notice The owner claims their rewards
    function claim(address to) external onlyOwnerOrApproved {
        uint256 amount = _handleEpochsClaim(_rate());

        // convert to external amount
        amount = amount.toExternal(paymentToken);
        totalClaimed += amount;

        paymentToken.safeTransfer(to, amount);

        emit FundsClaimed(amount, totalClaimed);
    }

    function claimable() public view returns (uint256) {
        (uint256 amount,,) = _processEpochs(_rate(), _currentEpoch());

        return amount.toExternal(paymentToken);
    }
}
