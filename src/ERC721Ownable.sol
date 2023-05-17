// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Context} from "openzeppelin-contracts/contracts/utils/Context.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

// forked from oz Ownable
// TODO comments
abstract contract ERC721Ownable is Context {
    address private _ownerContract;
    uint256 private _ownerTokenId;

    event OwnershipTransferred(address indexed previousOwnerContract,
                               uint256 indexed previousOwnerTokenId,
                               address indexed newOwnerContract,
                               uint256 newOwnerTokenId
                              );

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address, uint256) {
        return (_ownerContract, _ownerTokenId);
    }

    function ownerAddress() public view virtual returns (address) {
        return IERC721(_ownerContract).ownerOf(_ownerTokenId);
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(IERC721(_ownerContract).ownerOf(_ownerTokenId) == _msgSender(),
                "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0), 0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwnerContract, uint256 newOwnerTokenId) public virtual onlyOwner {
      // TODO check supportsInterface
        require(newOwnerContract != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwnerContract, newOwnerTokenId);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwnerContract, uint256 newOwnerTokenId) internal virtual {
        address oldOwnerContract = _ownerContract;
        uint256 oldOwnerTokenId = _ownerTokenId;
        _ownerContract = newOwnerContract;
        _ownerTokenId = newOwnerTokenId;
        emit OwnershipTransferred(oldOwnerContract, oldOwnerTokenId,
                                  newOwnerContract, newOwnerTokenId);
    }
}

