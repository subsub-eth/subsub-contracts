// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

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

abstract contract AbstractPropertiesFacet is
// Initializable,
    HasMaxSupply,
    HasMetadata,
    HasRate,
    HasHandleOwned,
    HasPaymentToken,
    HasUserData,
    HasEpochs,
    HasFlagSettings,
    HasValidation,
    // ERC721EnumerableUpgradeable,
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

abstract contract PropertiesFacet is
    // Validation,
    // Initializable,
    // Validation,
    ContextUpgradeable,
    // Validation,
    // ERC721EnumerableUpgradeable,
    ERC721Upgradeable,
    HandleOwned,
    MaxSupply,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    FlagSettings,
    TimestampTimeAware,
    // Validation,
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
}