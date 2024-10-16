// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MetadataStruct} from "./ISubscription.sol";

import {OzInitializable} from "../dependency/OzInitializable.sol";

library MetadataLib {
    struct MetadataStorage {
        string _description;
        string _image;
        string _externalUrl;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.Metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MetadataStorageLocation =
        0x4e23e702febef80da955bb4f7960279aadd3c90263ad7e053e89ad2bb31bf100;

    function _getMetadataStorage() private pure returns (MetadataStorage storage $) {
        assembly {
            $.slot := MetadataStorageLocation
        }
    }

    function init(string memory description, string memory image, string memory externalUrl) internal {
        MetadataStorage storage $ = _getMetadataStorage();
        $._description = description;
        $._image = image;
        $._externalUrl = externalUrl;
    }

    function metadata()
        internal
        view
        returns (string memory description, string memory image, string memory externalUrl)
    {
        MetadataStorage storage $ = _getMetadataStorage();
        description = $._description;
        image = $._image;
        externalUrl = $._externalUrl;
    }

    function setDescription(string calldata _description) internal {
        MetadataStorage storage $ = _getMetadataStorage();
        $._description = _description;
    }

    function setImage(string calldata _image) internal {
        MetadataStorage storage $ = _getMetadataStorage();
        $._image = _image;
    }

    function setExternalUrl(string calldata _externalUrl) internal {
        MetadataStorage storage $ = _getMetadataStorage();
        $._externalUrl = _externalUrl;
    }
}

abstract contract HasMetadata {
    function metadata()
        external
        view
        virtual
        returns (string memory description, string memory image, string memory externalUrl);

    function _setDescription(string calldata _description) internal virtual;

    function _setImage(string calldata _image) internal virtual;

    function _setExternalUrl(string calldata _externalUrl) internal virtual;
}

abstract contract Metadata is OzInitializable, HasMetadata {
    function __Metadata_init(string memory description, string memory image, string memory externalUrl)
        internal
    {
        __Metadata_init_unchained(description, image, externalUrl);
    }

    function __Metadata_init_unchained(string memory description, string memory image, string memory externalUrl)
        internal
    {
        __checkInitializing();
        MetadataLib.init(description, image, externalUrl);
    }

    function metadata()
        external
        view
        override
        returns (string memory description, string memory image, string memory externalUrl)
    {
        (description, image, externalUrl) = MetadataLib.metadata();
    }

    function _setDescription(string calldata _description) internal override {
        MetadataLib.setDescription(_description);
    }

    function _setImage(string calldata _image) internal override {
        MetadataLib.setImage(_image);
    }

    function _setExternalUrl(string calldata _externalUrl) internal override {
        MetadataLib.setExternalUrl(_externalUrl);
    }
}