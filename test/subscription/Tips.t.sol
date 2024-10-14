// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../../src/subscription/Tips.sol";

contract TestTips is Tips {
    function addTip(uint256 tokenId, uint256 amount) public {
        _addTip(tokenId, amount);
    }

    function tips(uint256 tokenId) public view returns (uint256) {
        return _tips(tokenId);
    }

    function allTips() public view returns (uint256) {
        return _allTips();
    }

    function claimedTips() public view returns (uint256) {
        return _claimedTips();
    }

    function claimableTips() public view returns (uint256) {
        return _claimableTips();
    }

    function claimTips() public returns (uint256) {
        return _claimTips();
    }
}

contract TipsTest is Test {
    using Math for uint256;

    TestTips private tt;

    uint256 private tokenId;

    function setUp() public {
        tokenId = 1;

        tt = new TestTips();
    }

    function testAddTip(uint256 _tokenId, uint256 amount) public {
        tt.addTip(_tokenId, amount);
        assertEq(amount, tt.tips(_tokenId), "Tip added to token");
        assertEq(amount, tt.allTips(), "Tip added to contract");
        assertEq(0, tt.claimedTips(), "No tips were claimed");
    }

    function testAddTip_incrementSingleToken(uint256 _tokenId, uint64[] memory amounts) public {
        uint256 allTips = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            allTips += amounts[i];
            tt.addTip(_tokenId, amounts[i]);

            assertEq(allTips, tt.tips(_tokenId), "Tip added to token");
            assertEq(allTips, tt.allTips(), "Tip added to contract");
            assertEq(0, tt.claimedTips(), "No tips were claimed");
        }
    }

    function testAddTip_incrementContract(uint256[] memory tokenIds, uint64 amount) public {
        uint256 allTips = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            allTips += amount;
            uint256 tokenTips = tt.tips(tokenIds[i]);

            tt.addTip(tokenIds[i], amount);
            assertEq(tokenTips + amount, tt.tips(tokenIds[i]), "Tip added to token");
            assertEq(allTips, tt.allTips(), "Tip added to contract");
            assertEq(0, tt.claimedTips(), "No tips were claimed");
        }
    }

    function testClaimTips(uint256 _tokenId, uint256 amount) public {
        tt.addTip(_tokenId, amount);

        assertEq(amount, tt.claimableTips(), "all tips claimable");

        uint256 claimed = tt.claimTips();

        assertEq(amount, claimed, "all tips claimed");
        assertEq(0, tt.claimableTips(), "no more tips to claim");
        assertEq(amount, tt.allTips(), "claimed tips still accounted for");
        assertEq(amount, tt.tips(_tokenId), "claimed tips in token still accounted for");
    }

    function testClaimTips_multiple(uint256[] memory tokenIds, uint64 amount) public {
        uint256 totalAmount = 0;
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalAmount += amount;
            tt.addTip(tokenIds[i], amount);

            uint256 claimed = tt.claimTips();
            assertEq(claimed, amount, "just tipped amount equals claimed");
            totalClaimed += claimed;
            assertEq(totalAmount, totalClaimed, "all claimed tips match total tips");

            assertEq(totalClaimed, tt.allTips(), "total claimed matches all tips");
            assertEq(totalClaimed, tt.claimedTips(), "total claimed matches all claimed tips");
        }
    }
}
