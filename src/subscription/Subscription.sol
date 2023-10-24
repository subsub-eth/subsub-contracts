// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription, MetadataStruct, SubSettings, SubscriptionFlags} from "./ISubscription.sol";
import {OwnableByERC721Upgradeable} from "../OwnableByERC721Upgradeable.sol";
import {SubscriptionLib} from "./SubscriptionLib.sol";
import {SubscriptionViewLib} from "./SubscriptionViewLib.sol";

import {TimeAware} from "./TimeAware.sol";
import {Epochs, HasEpochs} from "./Epochs.sol";
import {Rate, HasRate} from "./Rate.sol";
import {SubscriptionData, HasSubscriptionData} from "./SubscriptionData.sol";
import {PaymentToken, HasPaymentToken} from "./PaymentToken.sol";
import {MaxSupply, HasMaxSupply} from "./MaxSupply.sol";
import {Metadata, HasMetadata} from "./Metadata.sol";

import {HasFlagSettings, FlagSettings} from "../FlagSettings.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC165} from "openzeppelin-contracts/contracts/interfaces/IERC165.sol";
import {IERC721Metadata} from "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

// should the tokenId 0 == owner?

abstract contract Subscription is
    Initializable,
    ISubscription,
    TimeAware,
    HasMaxSupply,
    HasMetadata,
    HasRate,
    HasSubscriptionData,
    HasPaymentToken,
    HasEpochs,
    ERC721EnumerableUpgradeable,
    OwnableByERC721Upgradeable,
    SubscriptionFlags,
    HasFlagSettings
{
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using SubscriptionLib for uint256;
    using Strings for uint256;
    using Strings for address;

    using SubscriptionViewLib for Subscription;

    // TODO replace me?
    uint256 public nextTokenId;

    // external amount
    uint256 public totalClaimed;

    function __Subscription_init() internal onlyInitializing {
        __Subscription_init_unchained();
    }

    function __Subscription_init_unchained() internal onlyInitializing {}

    modifier requireExists(uint256 tokenId) {
        require(_ownerOf(tokenId) != address(0), "SUB: subscription does not exist");
        _;
    }

    modifier requireValidFlags(uint256 flags) {
        require(flags > 0, "SUB: invalid settings");
        require(flags <= ALL_FLAGS, "SUB: invalid settings");
        _;
    }

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings,
        address profileContract,
        uint256 profileTokenId
    ) external virtual;

    function settings()
        external
        view
        returns (IERC20Metadata token, uint256 rate, uint256 lock, uint256 epochSize, uint256 maxSupply_)
    {
        token = _paymentToken();
        rate = _rate();
        lock = _lock();
        epochSize = _epochSize();
        maxSupply_ = _maxSupply();
    }

    function setFlags(uint256 flags) external onlyOwnerOrApproved requireValidFlags(flags) {
        _setFlags(flags);
    }

    function unsetFlags(uint256 flags) external onlyOwnerOrApproved requireValidFlags(flags) {
        _unsetFlags(flags);
    }

    function setDescription(string calldata _description) external onlyOwnerOrApproved {
        _setDescription(_description);
    }

    function setImage(string calldata _image) external onlyOwnerOrApproved {
        _setImage(_image);
    }

    function setExternalUrl(string calldata _externalUrl) external onlyOwnerOrApproved {
        _setExternalUrl(_externalUrl);
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
        override(ERC721Upgradeable, IERC721Metadata)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "SUB: Token does not exist");

        return this.tokenData(tokenId);
    }

    function burn(uint256 tokenId) external {
        // only owner of tokenId can burn
        require(_msgSender() == _ownerOf(tokenId), "SUB: not the owner");

        _deleteSubscription(tokenId);

        _burn(tokenId);
    }

    /// @notice "Mints" a new subscription token
    function mint(uint256 amount, uint24 multiplier, string calldata message)
        external
        whenDisabled(MINTING_PAUSED)
        returns (uint256)
    {
        // check max supply
        require(totalSupply() < _maxSupply(), "SUB: max supply reached");
        // multiplier must be larger that 1x and less than 1000x
        // TODO in one call
        require(multiplier >= 100 && multiplier <= 100_000, "SUB: multiplier invalid");
        // TODO check minimum amount?
        // TODO handle 0 amount mints -> skip parts of code, new event type
        // uint subscriptionEnd = amount / rate;
        uint256 tokenId = nextTokenId++;
        uint256 mRate = _multipliedRate(multiplier);

        uint256 internalAmount = amount.toInternal(_decimals()).adjustToRate(mRate);

        _createSubscription(tokenId, internalAmount, multiplier);

        _addNewSubscriptionToEpochs(internalAmount, multiplier, mRate);

        // we transfer the ORIGINAL amount into the contract, claiming any overflows
        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

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
        uint256 internalAmount = amount.toInternal(_decimals()).adjustToRate(mRate);
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
        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(tokenId, amount, _totalDeposited(tokenId), msg.sender, message);
        emit MetadataUpdate(tokenId);
    }

    function withdraw(uint256 tokenId, uint256 amount) external requireExists(tokenId) {
        _withdraw(tokenId, amount.toInternal(_decimals()));
    }

    function cancel(uint256 tokenId) external requireExists(tokenId) {
        _withdraw(tokenId, _withdrawableFromSubscription(tokenId));
    }

    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(
            _isAuthorized(_ownerOf(tokenId), _msgSender(), tokenId), "ERC721: caller is not token owner or approved"
        );

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

        uint256 externalAmount = amount.toExternal(_decimals());
        _paymentToken().safeTransfer(_msgSender(), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, _totalDeposited(tokenId));
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function deposited(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _totalDeposited(tokenId).toExternal(_decimals());
    }

    function expiresAt(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _expiresAt(tokenId);
    }

    function withdrawable(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _withdrawableFromSubscription(tokenId).toExternal(_decimals());
    }

    function spent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (uint256 spentAmount,) = _spent(tokenId);
        return spentAmount.toExternal(_decimals());
    }

    function unspent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (, uint256 unspentAmount) = _spent(tokenId);
        return unspentAmount.toExternal(_decimals());
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        _incrementTotalDeposited(tokenId, amount.toInternal(_decimals()));

        _paymentToken().safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(tokenId, amount, _totalDeposited(tokenId), _msgSender(), message);
        emit MetadataUpdate(tokenId);
    }

    /// @notice The owner claims their rewards
    function claim(address to) external onlyOwnerOrApproved {
        uint256 amount = _handleEpochsClaim(_rate());

        // convert to external amount
        amount = amount.toExternal(_decimals());
        totalClaimed += amount;

        _paymentToken().safeTransfer(to, amount);

        emit FundsClaimed(amount, totalClaimed);
    }

    function claimable() public view returns (uint256) {
        (uint256 amount,,) = _processEpochs(_rate(), _currentEpoch());

        return amount.toExternal(_decimals());
    }
}

abstract contract DefaultSubscription is
    MaxSupply,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    SubscriptionData,
    FlagSettings,
    Subscription
{
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings,
        address profileContract,
        uint256 profileTokenId
    ) external override initializer {
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
        __PaymentToken_init_unchained(_settings.token);
        __MaxSupply_init_unchained(_settings.maxSupply);
        __Metadata_init_unchained(_metadata.description, _metadata.image, _metadata.externalUrl);

        nextTokenId = 1;

        // TODO check validity of token
    }
}
