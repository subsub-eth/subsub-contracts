// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lib} from "./Lib.sol";
import {HasRate} from "./Rate.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "forge-std/console.sol";

abstract contract HasTips {
    struct UserTips {
        uint256 tips; // amount of tips sent to this subscription
    }

    /**
     * @notice adds the given amount of funds to the tips of a subscription
     * @param tokenId subscription identifier
     * @param amount tip amount
     */
    function _addTip(uint256 tokenId, uint256 amount) internal virtual;

    /**
     * @notice returns the amount of tips placed in the given subscription
     * @param tokenId subscription identifier
     * @return the total amount of tips
     */
    function _tips(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice returns the amount of all tips placed in this contract
     * @return the total amount of tips in this contract
     */
    function _allTips() internal view virtual returns (uint256);

    /**
     * @notice returns the amount of tips that were claimed from this contract
     * @return the total amount of tips claimed from this contract
     */
    function _claimedTips() internal view virtual returns (uint256);

    /**
     * @notice returns the amount of tips that can be claimed from this contract
     * @dev returns the amount of not yet claimed tips
     * @return the amount of tips claimable from this contract
     */
    function _claimableTips() internal view virtual returns (uint256);

    /**
     * @notice claims the available tips from this contract
     * @return the amount of tips that were claimed by this call
     */
    function _claimTips() internal virtual returns (uint256);
}

abstract contract Tips is Initializable, HasTips {
    using Lib for uint256;

    struct TipsStorage {
        mapping(uint256 => UserTips) _userTips;
        // amount of tips EVER sent to the contract, the value only increments
        uint256 _allTips;
        // amount of tips EVER claimed from the contract, the value only increments
        uint256 _claimedTips;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.TipStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TipsStorageLocation =
        0xbf05d80824a4e35d926e60b1ca462d80f6b77fb9e9c7140da7f7231d82f47f00;

    function _getTipsStorage() private pure returns (TipsStorage storage $) {
        assembly {
            $.slot := TipsStorageLocation
        }
    }

    function __Tips_init() internal onlyInitializing {
        __Tips_init_unchained();
    }

    function __Tips_init_unchained() internal onlyInitializing {
    }


    function _addTip(uint256 tokenId, uint256 amount) internal override {
        TipsStorage storage $ = _getTipsStorage();
        // TODO change me
        $._userTips[tokenId].tips += amount;
        $._allTips += amount;
    }

    function _tips(uint256 tokenId) internal view override returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._userTips[tokenId].tips;
    }

    function _allTips() internal view override returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._allTips;
    }

    function _claimedTips() internal view override returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._claimedTips;
    }

    function _claimableTips() internal view override returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._allTips - $._claimedTips;
    }

    function _claimTips() internal override returns (uint256 claimable) {
        TipsStorage storage $ = _getTipsStorage();
        claimable = $._allTips - $._claimedTips;
        $._claimedTips = $._allTips;
    }
}