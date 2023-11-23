// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBadge.sol";

import {OwnableByERC721Upgradeable} from "../OwnableByERC721Upgradeable.sol";
import {MintAllowedUpgradeable} from "../MintAllowedUpgradeable.sol";

import {ERC1155Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

contract Badge is
    IBadge,
    ERC1155SupplyUpgradeable,
    ERC1155BurnableUpgradeable,
    OwnableByERC721Upgradeable,
    MintAllowedUpgradeable
{
    // TODO add royalties?

    mapping(uint256 => TokenData) private _tokenData;

    uint256 private _nextId;

    constructor() {
        _disableInitializers();
    }

    function initialize(address profileContract, uint256 profileTokenId) external initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC1155_init_unchained("");
        __ERC1155Supply_init_unchained();
        __ERC1155Burnable_init_unchained();
        __OwnableByERC721_init_unchained(profileContract, profileTokenId);
        __MintAllowedUpgradeable_init_unchained();

        _nextId = 1;
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory data) external {
        _requireMintAllowed(id);
        require(_tokenData[id].maxSupply - totalSupply(id) >= amount, "Badge: exceeds token's max supply");
        require(type(uint256).max - totalSupply() >= amount, "Badge: exceeds contract's max supply");

        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external {
        for (uint256 i = 0; i < ids.length; i++) {
            _requireMintAllowed(ids[i]);
            require(
                _tokenData[ids[i]].maxSupply - totalSupply(ids[i]) >= amounts[i], "Badge: exceeds token's max supply"
            );
            require(type(uint256).max - totalSupply() >= amounts[i], "Badge: exceeds contract's max supply");
        }

        _mintBatch(to, ids, amounts, data);
    }

    function burn(address account, uint256 id, uint256 value)
        public
        override(IBadgeOperations, ERC1155BurnableUpgradeable)
    {
        super.burn(account, id, value);
    }

    function burnBatch(address account, uint256[] memory ids, uint256[] memory values)
        public
        override(IBadgeOperations, ERC1155BurnableUpgradeable)
    {
        super.burnBatch(account, ids, values);
    }

    function createToken(TokenData memory tokenData) external onlyOwnerOrApproved returns (uint256 id) {
        require(tokenData.maxSupply > 0, "Badge: new token maxSupply == 0");

        id = _nextId++;

        _tokenData[id] = tokenData;

        emit TokenCreated(_msgSender(), id);
    }

    function setMintAllowed(address minter, uint256 id, bool allow)
        public
        override(IMintAllowedUpgradeable, MintAllowedUpgradeable)
        onlyOwnerOrApproved
    {
        super.setMintAllowed(minter, id, allow);
    }

    function _idExists(uint256 id) internal view override returns (bool) {
        return exists(id);
    }

    function exists(uint256 id) public view override returns (bool) {
        return id < _nextId && id > 0;
    }

    function latestId() external returns (uint256) {
        return _nextId - 1;
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override(ERC1155SupplyUpgradeable, ERC1155Upgradeable)
    {
        super._update(from, to, ids, values);
    }
}
