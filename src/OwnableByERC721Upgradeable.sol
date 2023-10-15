// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

/**
 * @dev copied from OZ upgradeable contracts, changed to use an ERC721 for
 * ownership.
 *
 * Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
// TODO fix comments
// TODO check contract to an ERC721 contract
abstract contract OwnableByERC721Upgradeable is Initializable, ContextUpgradeable {
    struct OwnableByERC721Storage {
        address _ownerContract;
        uint256 _ownerTokenId;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.OwnableByERC721")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableByERC721StorageLocation =
        0xa78a34013f9a428a84ac0d319baa6ed0f0fdf3d94a253ec4b1b045a1bdc65e00;

    function _getOwnableByERC721Storage() private pure returns (OwnableByERC721Storage storage $) {
        assembly {
            $.slot := OwnableByERC721StorageLocation
        }
    }

    event OwnershipTransferred(
        address indexed previousOwnerContract,
        uint256 indexed previousOwnerTokenId,
        address indexed newOwnerContract,
        uint256 newOwnerTokenId
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __OwnableByERC721_init(address ownerContract, uint256 ownerTokenId) internal onlyInitializing {
        __OwnableByERC721_init_unchained(ownerContract, ownerTokenId);
    }

    function __OwnableByERC721_init_unchained(address ownerContract, uint256 ownerTokenId) internal onlyInitializing {
        _transferOwnership(ownerContract, ownerTokenId);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Throws if called by any account other than the owner or an approved one.
     */
    modifier onlyOwnerOrApproved() {
        _checkOwnerOrApproved();
        _;
    }

    /**
     * @dev Returns the ERC721 contract address and the tokenId
     */
    function owner() public view virtual returns (address, uint256) {
        OwnableByERC721Storage storage $ = _getOwnableByERC721Storage();
        return ($._ownerContract, $._ownerTokenId);
    }

    /**
     * @dev Returns the owner of the token in the ERC721 contract, address(0)
     * if the contract is set to address(0)
     */
    function ownerAddress() public view virtual returns (address) {
        OwnableByERC721Storage storage $ = _getOwnableByERC721Storage();
        if ($._ownerContract == address(0)) {
            return address(0);
        }
        return IERC721($._ownerContract).ownerOf($._ownerTokenId);
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(ownerAddress() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Throws if the sender is not approved
     */
    function _checkOwnerOrApproved() internal view virtual {
        OwnableByERC721Storage storage $ = _getOwnableByERC721Storage();
        address _owner = ownerAddress();
        require(
            _owner == _msgSender() || IERC721($._ownerContract).isApprovedForAll(_owner, _msgSender())
                || IERC721($._ownerContract).getApproved($._ownerTokenId) == _msgSender(),
            "Ownable: caller is not owner or approved"
        );
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwnerContract, uint256 newOwnerTokenId) internal virtual {
        OwnableByERC721Storage storage $ = _getOwnableByERC721Storage();
        address oldOwnerContract = $._ownerContract;
        uint256 oldOwnerTokenId = $._ownerTokenId;
        $._ownerContract = newOwnerContract;
        $._ownerTokenId = newOwnerTokenId;
        emit OwnershipTransferred(oldOwnerContract, oldOwnerTokenId, newOwnerContract, newOwnerTokenId);
    }
}

abstract contract TransferableOwnableByERC721Upgradeable is OwnableByERC721Upgradeable {
    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
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
        require(newOwnerContract != address(0), "Ownable: new owner contract is the zero address");
        _transferOwnership(newOwnerContract, newOwnerTokenId);
    }
}
