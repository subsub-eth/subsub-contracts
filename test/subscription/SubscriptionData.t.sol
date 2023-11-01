// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/SubscriptionData.sol";

contract TestSubscriptionData is SubscriptionData {
    constructor(uint256 lock) initializer {
        __SubscriptionData_init(lock);
    }

    function _now() internal view override returns (uint256) {
        return block.number;
    }

    function _multipliedRate(uint256 multiplier) internal view override returns (uint256) {}

    function _rate() internal view override returns (uint256) {}

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

contract SubscriptionDataTest is Test {
    TestSubscriptionData private sd;

    uint256 private lock;

    function setUp() public {
        lock = 100;

        sd = new TestSubscriptionData(lock);
    }

    function testAddTip(uint256 tokenId, uint256 amount) public {
        sd.addTip(tokenId, amount);
        assertEq(amount, sd.tips(tokenId), "Tip added to token");
        assertEq(amount, sd.allTips(), "Tip added to contract");
        assertEq(0, sd.claimedTips(), "No tips were claimed");
    }

    function testAddTip_incrementSingleToken(uint256 tokenId, uint64[] memory amounts) public {
        uint256 allTips = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            allTips += amounts[i];
            sd.addTip(tokenId, amounts[i]);

            assertEq(allTips, sd.tips(tokenId), "Tip added to token");
            assertEq(allTips, sd.allTips(), "Tip added to contract");
            assertEq(0, sd.claimedTips(), "No tips were claimed");
        }
    }

    function testAddTip_incrementContract(uint256[] memory tokenIds, uint64 amount) public {
        uint256 allTips = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            allTips += amount;
            uint256 tokenTips = sd.tips(tokenIds[i]);

            sd.addTip(tokenIds[i], amount);
            assertEq(tokenTips + amount, sd.tips(tokenIds[i]), "Tip added to token");
            assertEq(allTips, sd.allTips(), "Tip added to contract");
            assertEq(0, sd.claimedTips(), "No tips were claimed");
        }
    }

    function testClaimTips(uint256 tokenId, uint256 amount) public {
        sd.addTip(tokenId, amount);

        assertEq(amount, sd.claimableTips(),"all tips claimable");

        uint256 claimed = sd.claimTips();

        assertEq(amount, claimed, "all tips claimed");
        assertEq(0, sd.claimableTips(),"no more tips to claim");
        assertEq(amount, sd.allTips(), "claimed tips still accounted for");
        assertEq(amount, sd.tips(tokenId), "claimed tips in token still accounted for");
    }

    function testClaimTips_multiple(uint256[] memory tokenIds, uint64 amount) public {
        uint256 totalAmount = 0;
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalAmount += amount;
            sd.addTip(tokenIds[i], amount);

            uint256 claimed = sd.claimTips();
            assertEq(claimed, amount, "just tipped amount equals claimed");
            totalClaimed += claimed;
            assertEq(totalAmount, totalClaimed, "all claimed tips match total tips");

            assertEq(totalClaimed, sd.allTips(), "total claimed matches all tips");
            assertEq(totalClaimed, sd.claimedTips(), "total claimed matches all claimed tips");
        }
    }
}
