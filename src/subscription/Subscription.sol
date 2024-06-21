// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription, MetadataStruct, SubSettings, SubscriptionFlags} from "./ISubscription.sol";
import {Lib} from "./Lib.sol";
import {ViewLib} from "./ViewLib.sol";

import {TimeAware} from "./TimeAware.sol";
import {Epochs, HasEpochs} from "./Epochs.sol";
import {Rate, HasRate} from "./Rate.sol";
import {UserData, HasUserData} from "./UserData.sol";
import {PaymentToken, HasPaymentToken} from "./PaymentToken.sol";
import {MaxSupply, HasMaxSupply} from "./MaxSupply.sol";
import {Metadata, HasMetadata} from "./Metadata.sol";
import {HandleOwned, HasHandleOwned} from "../handle/HandleOwned.sol";

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

// responsbile for handling conversion of token amounts between internal and external representation
abstract contract Subscription is
    Initializable,
    ISubscription,
    TimeAware,
    HasMaxSupply,
    HasMetadata,
    HasRate,
    HasUserData,
    HasPaymentToken,
    HasEpochs,
    HasHandleOwned,
    ERC721EnumerableUpgradeable,
    SubscriptionFlags,
    HasFlagSettings
{
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using Lib for uint256;
    using Strings for uint256;
    using Strings for address;

    using ViewLib for Subscription;

    // TODO replace me?
    uint256 public nextTokenId;

    function __Subscription_init() internal onlyInitializing {
        __Subscription_init_unchained();
    }

    function __Subscription_init_unchained() internal onlyInitializing {}

    modifier requireExists(uint256 tokenId) {
        require(_ownerOf(tokenId) != address(0), "SUB: subscription does not exist");
        _;
    }

    modifier requireValidFlags(uint256 flags) {
        require(flags <= ALL_FLAGS, "SUB: invalid settings");
        _;
    }

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external virtual;

    function settings()
        external
        view
        returns (IERC20Metadata token, uint256 rate, uint24 lock, uint256 epochSize, uint256 maxSupply_)
    {
        token = _paymentToken();
        rate = _rate();
        lock = _lock();
        epochSize = _epochSize();
        maxSupply_ = _maxSupply();
    }

    function epochState() external view returns (uint256 currentEpoch, uint256 lastProcessedEpoch) {
        currentEpoch = _currentEpoch();
        lastProcessedEpoch = _lastProcessedEpoch();
    }

    function setFlags(uint256 flags) external onlyOwner requireValidFlags(flags) {
        _setFlags(flags);
    }

    function setDescription(string calldata _description) external onlyOwner {
        _setDescription(_description);
    }

    function setImage(string calldata _image) external onlyOwner {
        _setImage(_image);
    }

    function setExternalUrl(string calldata _externalUrl) external onlyOwner {
        _setExternalUrl(_externalUrl);
    }

    function contractURI() external view returns (string memory) {
        return this.contractData();
    }

    function claimed() external view returns (uint256) {
        return _claimed().toExternal(_decimals());
    }

    function claimedTips() external view returns (uint256) {
        return _claimedTips().toExternal(_decimals());
    }

    function activeSubShares() external view returns (uint256) {
        return _activeSubShares();
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

        // TODO do we need return values?
        _createSubscription(tokenId, internalAmount, multiplier);

        _addToEpochs(internalAmount, multiplier, mRate);

        // we transfer the ORIGINAL amount into the contract, claiming any overflows / dust
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
            (uint64 oldDeposit, uint256 newDeposit, uint256 lastDepositedAt, bool reactived) =
                _extendSubscription(tokenId, internalAmount);

            if (reactived) {
                // subscription was inactive
                _addToEpochs(newDeposit, multiplier, mRate);
            } else {
                _moveInEpochs(lastDepositedAt, oldDeposit, _now(), newDeposit, multiplier, mRate);
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

        // TODO do not allow funds from the current time slot
        // TODO move to withdraw
        uint256 withdrawable_ = _withdrawableFromSubscription(tokenId);

        // TODO remove, check in UserData
        require(amount <= withdrawable_, "SUB: amount exceeds withdrawable");

        uint256 _lastDepositAt = _lastDepositedAt(tokenId);
        (uint64 depositedAt, uint256 oldDeposit, uint256 newDeposit) = _withdrawFromSubscription(tokenId, amount);

        uint256 multiplier_ = _multiplier(tokenId);
        _moveInEpochs(
            _lastDepositAt,
            oldDeposit,
            _lastDepositAt,
            newDeposit,
            multiplier_,
            // TODO weird?
            _multipliedRate(multiplier_)
        );

        uint256 externalAmount = amount.toExternal(_decimals());
        _paymentToken().safeTransfer(_msgSender(), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, _totalDeposited(tokenId));
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function multiplier(uint256 tokenId) external view returns (uint24) {
        return _multiplier(tokenId);
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

    function tips(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _tips(tokenId).toExternal(_decimals());
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        _addTip(tokenId, amount.toInternal(_decimals()));

        _paymentToken().safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(tokenId, amount, _tips(tokenId).toExternal(_decimals()), _msgSender(), message);
        emit MetadataUpdate(tokenId);
    }

    /// @notice The owner claims their rewards
    function claim(address to) external onlyOwner {
        uint256 amount = _claimEpochs(_rate());
        amount += _claimTips();

        // convert to external amount
        amount = amount.toExternal(_decimals());

        _paymentToken().safeTransfer(to, amount);

        emit FundsClaimed(amount, _claimed().toExternal(_decimals()));
    }

    function claimable(uint256 startEpoch, uint256 endEpoch) public view returns (uint256) {
        (uint256 amount,,) = _scanEpochs(_rate(), _currentEpoch());

        return amount.toExternal(_decimals());
    }

    function claimable() external view returns (uint256) {
        return claimable(_lastProcessedEpoch(), _currentEpoch());
    }

    function claimTips(address to) external onlyOwner {
        uint256 amount = _claimTips();

        // convert to external amount
        amount = amount.toExternal(_decimals());

        _paymentToken().safeTransfer(to, amount);

        emit TipsClaimed(amount, _claimedTips().toExternal(_decimals()));
    }

    function claimableTips() external view returns (uint256) {
        return _claimableTips().toExternal(_decimals());
    }
}

abstract contract DefaultSubscription is
    MaxSupply,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    HandleOwned,
    FlagSettings,
    Subscription
{
    constructor(address handleContract) HandleOwned(handleContract) {
        _disableInitializers();
    }

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external override initializer {
        require(_settings.epochSize > 0, "SUB: invalid epochSize");
        require(address(_settings.token) != address(0), "SUB: token cannot be 0 address");
        require(_settings.lock <= 10_000, "SUB: lock percentage out of range");
        require(_settings.rate > 0, "SUB: rate cannot be 0");
        // TODO FIXME
        // require(_settings.epochSize >= 1 days, "SUB: epoch size has to be at least 1 day");

        // call initializers of inherited contracts
        __ERC721_init_unchained(tokenName, tokenSymbol);
        __FlagSettings_init_unchained();
        __Rate_init_unchained(_settings.rate);
        __Epochs_init_unchained(_settings.epochSize);
        __UserData_init_unchained(_settings.lock);
        __PaymentToken_init_unchained(_settings.token);
        __MaxSupply_init_unchained(_settings.maxSupply);
        __Metadata_init_unchained(_metadata.description, _metadata.image, _metadata.externalUrl);

        nextTokenId = 1;
    }
}