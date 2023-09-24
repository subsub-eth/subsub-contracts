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
        require(_tokenData[id].maxSupply >= amount + totalSupply(id), "Badge: exceeds max supply");

        _mint(to, id, amount, data);
    }

    function burn(address account, uint256 id, uint256 value) public override(IBadge, ERC1155BurnableUpgradeable) {
        super.burn(account, id, value);
    }

    function createToken(TokenData memory tokenData) external onlyOwner returns (uint256 id) {
        require(tokenData.maxSupply > 0, "Badge: new token maxSupply == 0");

        id = _nextId++;

        _tokenData[id] = tokenData;

        // TODO emit event
    }

    function setMintAllowed(address minter, uint256 id, bool allow)
        public
        override(IMintAllowedUpgradeable, MintAllowedUpgradeable)
        onlyOwner
    {
        super.setMintAllowed(minter, id, allow);
    }

    function _idExists(uint256 id) internal view override returns (bool) {
        return exists(id);
    }

    function exists(uint256 id) public view override returns (bool) {
        // TODO find better implementation
        return _tokenData[id].maxSupply > 0;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155SupplyUpgradeable, ERC1155Upgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
