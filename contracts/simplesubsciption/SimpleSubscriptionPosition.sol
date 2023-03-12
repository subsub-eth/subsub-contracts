// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "@openzeppelin/contracts/utils/Counters.sol";

contract SimpleSubscriptionPosition is
  Ownable,
  ERC721Enumerable,
  ERC721URIStorage {

  using Counters for Counters.Counter;


  Counters.Counter private _tokenIdCount;

  constructor()
    Ownable()
    ERC721("SimpleCreatezPositionV0", "pCRZv0") {
  }

  /**
   * @dev mint a new subscription contract
   **/
  function mint (
      address to,
      IERC721 vaultToken
    )
    public
    onlyOwner
    returns (uint256) {

    _tokenIdCount.increment();
    _safeMint(to, _tokenIdCount.current());

    return _tokenIdCount.current();
  }

  function tokenURI(uint256 tokenId)
    public
    view
    override (ERC721, ERC721URIStorage)
    returns (string memory) {

    return "";
  }

  function _burn(uint256 tokenId)
    internal
    virtual
    override(ERC721, ERC721URIStorage) {
    super._burn(tokenId);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal virtual override(ERC721, ERC721Enumerable) {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
