// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscription, MetadataStruct, SubSettings, SubscriptionFlags} from "./ISubscription.sol";
import {Lib} from "./Lib.sol";
import {ViewLib} from "./ViewLib.sol";

import {TimeAware} from "./TimeAware.sol";
import {TokenIdProvider, HasTokenIdProvider} from "./TokenIdProvider.sol";
import {Epochs, HasEpochs} from "./Epochs.sol";
import {Rate, HasRate} from "./Rate.sol";
import {UserData, HasUserData} from "./UserData.sol";
import {Tips, HasTips} from "./Tips.sol";
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

// responsbile for handling conversion of token amounts between internal and external representation
abstract contract Subscription is
    Initializable,
    ISubscription,
    TimeAware,
    HasMaxSupply,
    HasTokenIdProvider,
    HasMetadata,
    HasRate,
    HasUserData,
    HasTips,
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

    /**
     * @notice converts an mount to the internal representation
     * @param amount the external representation
     * @return the internal representation
     *
     */
    function _asInternal(uint256 amount) internal view virtual returns (uint256) {
        return amount.toInternal(_decimals());
    }

    /**
     * @notice converts an mount to the internal representation
     * @param amount the internal representation
     * @return the external representation
     *
     */
    function _asExternal(uint256 amount) internal view virtual returns (uint256) {
        return amount.toExternal(_decimals());
    }

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
        return _asExternal(_claimed());
    }

    function claimedTips() external view returns (uint256) {
        return _asExternal(_claimedTips());
    }

    function activeSubShares() external view returns (uint256) {
        return _activeSubShares();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC721Metadata)
        requireExists(tokenId)
        returns (string memory)
    {
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
        require(multiplier >= Lib.MULTIPLIER_BASE && multiplier <= 100_000, "SUB: multiplier invalid");
        // uint subscriptionEnd = amount / rate;
        uint256 tokenId = _nextTokenId();

        uint256 internalAmount = _asInternal(amount);

        // TODO do we need return values?
        _createSubscription(tokenId, internalAmount, multiplier);

        _addToEpochs(_now(), internalAmount, multiplier, _rate());

        // we transfer the ORIGINAL amount into the contract, claiming any overflows / dust
        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        emit SubscriptionRenewed(tokenId, amount, _msgSender(), _totalDeposited(tokenId), message);

        return tokenId;
    }

    /// @notice adds deposits to an existing subscription token
    function renew(uint256 tokenId, uint256 amount, string calldata message)
        external
        whenDisabled(RENEWAL_PAUSED)
        requireExists(tokenId)
    {
        uint256 multiplier_ = _multiplier(tokenId);
        uint256 rate = _rate();
        uint256 internalAmount = _asInternal(amount);

        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactived) =
                _extendSubscription(tokenId, internalAmount);

            if (reactived) {
                // subscription was inactive, new streak was created, add "new" sub to epochs
                _addToEpochs(_now(), newDeposit, multiplier_, rate);
            } else {
                _extendInEpochs(depositedAt, oldDeposit, newDeposit, multiplier_, rate);
            }
        }

        // finally transfer tokens into this contract
        // we use the ORIGINAL amount here
        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(tokenId, amount, _msgSender(), _totalDeposited(tokenId), message);
        emit MetadataUpdate(tokenId);
    }

    function changeMultiplier(uint256 tokenId, uint24 newMultiplier) external requireExists(tokenId) {
        require(
            _isAuthorized(_ownerOf(tokenId), _msgSender(), tokenId), "ERC721: caller is not token owner or approved"
        );
        // TODO check validity of multiplier

        (bool isActive_, MultiplierChanged memory change) = _changeMultiplier(tokenId, newMultiplier);

        if (isActive_) {
            uint256 rate = _rate();
            _reduceInEpochs(change.oldDepositAt, change.oldAmount, change.reducedAmount, change.oldMultiplier, rate);

            _addToEpochs(change.newDepositAt, change.newAmount, newMultiplier, rate);
        }
        // else => inactive subs are effectively not tracked in Epochs, thus no further changes as necessary

        // TODO emit some event
    }

    function withdraw(uint256 tokenId, uint256 amount) external requireExists(tokenId) {
        _withdraw(tokenId, _asInternal(amount));
    }

    function cancel(uint256 tokenId) external requireExists(tokenId) {
        _withdraw(tokenId, _withdrawableFromSubscription(tokenId));
    }

    /**
     * @param amount internal representation (18 decimals) of amount to withdraw
     *
     */
    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(
            _isAuthorized(_ownerOf(tokenId), _msgSender(), tokenId), "ERC721: caller is not token owner or approved"
        );

        // amount is checked in _withdrawFromSubscription
        (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) = _withdrawFromSubscription(tokenId, amount);

        _reduceInEpochs(depositedAt, oldDeposit, newDeposit, _multiplier(tokenId), _rate());

        uint256 externalAmount = _asExternal(amount);
        _paymentToken().safeTransfer(_msgSender(), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, _msgSender(), _totalDeposited(tokenId));
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function multiplier(uint256 tokenId) external view returns (uint24) {
        return _multiplier(tokenId);
    }

    function deposited(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _asExternal(_totalDeposited(tokenId));
    }

    function expiresAt(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _expiresAt(tokenId);
    }

    function withdrawable(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _asExternal(_withdrawableFromSubscription(tokenId));
    }

    function spent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (uint256 spentAmount,) = _spent(tokenId);
        return _asExternal(spentAmount);
    }

    function unspent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (, uint256 unspentAmount) = _spent(tokenId);
        return _asExternal(unspentAmount);
    }

    function tips(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _tips(tokenId);
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        _addTip(tokenId, amount);

        _paymentToken().safeTransferFrom(_msgSender(), address(this), amount);

        emit Tipped(tokenId, amount, _msgSender(), _tips(tokenId), message);
        emit MetadataUpdate(tokenId);
    }

    /// @notice The owner claims their rewards
    function claim(address to) external {
        claim(to, _currentEpoch());
    }

    function claim(address to, uint256 upToEpoch) public onlyOwner {
        // epochs validity is checked in _claimEpochs
        uint256 amount = _claimEpochs(_rate(), upToEpoch);

        // convert to external amount
        amount = _asExternal(amount);

        _paymentToken().safeTransfer(to, amount);

        emit FundsClaimed(amount, _asExternal(_claimed()));
    }

    function claimable(uint256 startEpoch, uint256 endEpoch) public view returns (uint256) {
        (uint256 amount,,) = _scanEpochs(_rate(), _currentEpoch());

        return _asExternal(amount);
    }

    function claimable() external view returns (uint256) {
        return claimable(_lastProcessedEpoch(), _currentEpoch());
    }

    function claimTips(address to) external onlyOwner {
        uint256 amount = _claimTips();

        _paymentToken().safeTransfer(to, amount);

        emit TipsClaimed(amount, _claimedTips());
    }

    function claimableTips() external view returns (uint256) {
        return _claimableTips();
    }
}

abstract contract DefaultSubscription is
    MaxSupply,
    TokenIdProvider,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    Tips,
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
        require(_settings.lock <= Lib.LOCK_BASE, "SUB: lock percentage out of range");
        require(_settings.rate > 0, "SUB: rate cannot be 0");
        // TODO FIXME
        // require(_settings.epochSize >= 1 days, "SUB: epoch size has to be at least 1 day");

        // call initializers of inherited contracts
        __ERC721_init_unchained(tokenName, tokenSymbol);
        __FlagSettings_init_unchained();
        __Rate_init_unchained(_settings.rate);
        __Epochs_init_unchained(_settings.epochSize);
        __UserData_init_unchained(_settings.lock);
        __Tips_init_unchained();
        __PaymentToken_init_unchained(_settings.token);
        __MaxSupply_init_unchained(_settings.maxSupply);
        __TokenIdProvider_init_unchained(0);
        __Metadata_init_unchained(_metadata.description, _metadata.image, _metadata.externalUrl);
    }
}