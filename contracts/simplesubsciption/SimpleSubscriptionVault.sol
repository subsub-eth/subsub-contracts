// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SimpleSubscriptionPosition.sol";

import "../util/Blockaware.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "@openzeppelin/contracts/utils/Counters.sol";

contract SimpleSubscriptionVault is
  Blockaware,
  ERC721Enumerable,
  ERC721URIStorage {

  using Counters for Counters.Counter;

  SimpleSubscriptionPosition private _positionToken;

  Counters.Counter private _tokenIdCount;

  constructor(SimpleSubscriptionPosition positionToken)
    ERC721("SimpleCreatezVaultV0", "vCRZv0") {
      _positionToken = positionToken;
  }


  /**
   * @dev mint a new subscription contract
   **/
  function mint(IERC20 subscriptionToken) public returns (uint256){
    _tokenIdCount.increment();
    _safeMint(_msgSender(), _tokenIdCount.current());
    // TODO setup subscription data

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
