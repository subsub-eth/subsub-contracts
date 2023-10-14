// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MetadataStruct} from "./ISubscription.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract HasMetadata {

    function metadata() external virtual view returns (string memory description, string memory image, string memory externalUrl);

    function _setDescription(string calldata _description) internal virtual;

    function _setImage(string calldata _image) internal virtual;

    function _setExternalUrl(string calldata _externalUrl) internal virtual;
}

abstract contract Metadata is Initializable, HasMetadata {

    MetadataStruct private __metadata;

    function __Metadata_init(MetadataStruct memory _metadata) internal onlyInitializing {
        __Metadata_init_unchained(_metadata);
    }

    function __Metadata_init_unchained(MetadataStruct memory _metadata) internal onlyInitializing {
      __metadata = _metadata;
    }


    function metadata() external override view returns (string memory description, string memory image, string memory externalUrl) {
      description = __metadata.description;
      image = __metadata.image;
      externalUrl = __metadata.externalUrl;
    }

    function _setDescription(string calldata _description) internal override {
        __metadata.description = _description;
    }

    function _setImage(string calldata _image) internal override {
        __metadata.image = _image;
    }

    function _setExternalUrl(string calldata _externalUrl) internal override {
        __metadata.externalUrl = _externalUrl;
    }

    // TODO _gap
}

