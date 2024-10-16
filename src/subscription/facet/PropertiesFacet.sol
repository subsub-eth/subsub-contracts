// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import {SubscriptionProperties} from "../ISubscription.sol";
import {HasHandleOwned, HandleOwned} from "../../handle/HandleOwned.sol";
import {HasValidation, Validation} from "../Validation.sol";
import {Epochs, HasEpochs} from "../Epochs.sol";
import {Rate, HasRate} from "../Rate.sol";
import {UserData, HasUserData} from "../UserData.sol";
import {PaymentToken, HasPaymentToken} from "../PaymentToken.sol";
import {Metadata, HasMetadata} from "../Metadata.sol";
import {MaxSupply, HasMaxSupply} from "../MaxSupply.sol";
import {TimestampTimeAware} from "../TimeAware.sol";
import {HasFlagSettings, FlagSettings} from "../../FlagSettings.sol";

import {OzContext} from "../../dependency/OzContext.sol";
import {OzERC721Enumerable} from "../../dependency/OzERC721Enumerable.sol";
import {OzInitializable} from "../../dependency/OzInitializable.sol";

abstract contract AbstractPropertiesFacet is
    HasMaxSupply,
    HasMetadata,
    HasRate,
    HasHandleOwned,
    HasPaymentToken,
    HasUserData,
    HasEpochs,
    HasFlagSettings,
    HasValidation,
    SubscriptionProperties
{
    function settings()
        external
        view
        returns (address token, uint256 rate, uint24 lock, uint256 epochSize, uint256 maxSupply_)
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
}

contract PropertiesFacet is
    TimestampTimeAware,
    ContextUpgradeable,
    HandleOwned,
    MaxSupply,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    FlagSettings,
    Validation,
    ERC721EnumerableUpgradeable,
    AbstractPropertiesFacet
{
    constructor(address handleContract) HandleOwned(handleContract) {
        _disableInitializers();
    }

    /**
     * Interface late bindings
     */
    function _msgSender() internal view virtual override(ContextUpgradeable, OzContext) returns (address) {
        return ContextUpgradeable._msgSender();
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data)
        internal
        virtual
        override(ERC721Upgradeable, OzERC721Enumerable)
    {
        ERC721Upgradeable._safeMint(to, tokenId, data);
    }

    function totalSupply()
        public
        view
        virtual
        override(ERC721EnumerableUpgradeable, OzERC721Enumerable)
        returns (uint256)
    {
        return ERC721EnumerableUpgradeable.totalSupply();
    }

    function _ownerOf(uint256 tokenId)
        internal
        view
        virtual
        override(ERC721Upgradeable, OzERC721Enumerable)
        returns (address)
    {
        return ERC721Upgradeable._ownerOf(tokenId);
    }

    function _isAuthorized(address owner, address spender, uint256 tokenId)
        internal
        view
        virtual
        override(ERC721Upgradeable, OzERC721Enumerable)
        returns (bool)
    {
        return ERC721Upgradeable._isAuthorized(owner, spender, tokenId);
    }

    function _checkInitializing() internal view virtual override(Initializable, OzInitializable) {
        Initializable._checkInitializing();
    }
}