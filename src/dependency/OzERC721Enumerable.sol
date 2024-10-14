// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev internal interface exposing OZ {ERC721Enumerable} methods without
 * binding to the implementation. The actually implementation needs to be
 * overriden later.
 */
abstract contract OzERC721Enumerable {
    // IERC721Enumerable just defines an external method but we need public
    function totalSupply() public view virtual returns (uint256);
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual;

    function _ownerOf(uint256 tokenId) internal view virtual returns (address);

    function _isAuthorized(address owner, address spender, uint256 tokenId) internal view virtual returns (bool);
}