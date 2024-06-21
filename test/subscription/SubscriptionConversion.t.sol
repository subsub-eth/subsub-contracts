// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/subscription/Subscription.sol";
import "../mocks/TestSubscription.sol";

import {SubscriptionEvents, ClaimEvents} from "../../src/subscription/ISubscription.sol";
import {Lib} from "../../src/subscription/Lib.sol";
import "../../src/subscription/handle/SubscriptionHandle.sol";

import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SubscriptionConversionTest is Test, SubscriptionEvents, ClaimEvents {
    using Lib for uint256;

    ERC1967Proxy public subscriptionProxy;
    TestSubscription public subscriptionImplementation;
    TestSubscription public subscription;
    ERC20DecimalsMock public testToken;
    SubscriptionHandle public handle;
    uint256 public rate;
    uint24 public lock;
    uint64 public epochSize;
    uint256 public maxSupply;

    address public owner;
    uint256 public ownerTokenId;
    address public alice;
    address public bob;
    address public charlie;

    string public message;

    MetadataStruct public metadata;
    SubSettings public settings;

    uint64 public currentTime;

    function setCurrentTime(uint64 newTime) internal {
        currentTime = newTime;
        subscription.setNow(newTime);
    }

    function setUp() public {
        owner = address(1);
        alice = address(10);

        message = "Hello World";

        metadata = MetadataStruct("test", "test", "test");

        rate = 3 ether / 1000; // 0.003 tokens per block
        lock = 100;
        epochSize = 100;
        maxSupply = 10_000;

        handle = new SimpleSubscriptionHandle(address(0));
    }

    function createContracts(uint8 decimals) private {
        testToken = new ERC20DecimalsMock(decimals);
        settings = SubSettings(testToken, rate, lock, epochSize, maxSupply);

        // init simple proxy setup
        subscriptionImplementation = new TestSubscription(address(handle));
        subscriptionProxy = new ERC1967Proxy(
            address(subscriptionImplementation),
            ""
        );
        subscription = TestSubscription(address(subscriptionProxy));
        subscription.setNow(currentTime);
        subscription.initialize("test", "test", metadata, settings);

        vm.prank(owner);
        handle.register(address(subscription));

        testToken.approve(address(subscription), type(uint256).max);

        testToken.mint(alice, UINT256_MAX);
    }

    function mintToken(address user, uint256 amount) private returns (uint256 tokenId) {
        vm.startPrank(user);
        testToken.approve(address(subscription), amount);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(
            subscription.totalSupply() + 1, amount, amount.toInternal(testToken.decimals()).adjustToRate(rate), user, message
        );

        tokenId = subscription.mint(amount, 100, message);
        vm.stopPrank();
        assertEq(testToken.balanceOf(address(subscription)), amount, "amount send to subscription contract");

        uint256 lockedAmount = (amount.toInternal(testToken.decimals()) * lock) / subscription.LOCK_BASE();
        lockedAmount = lockedAmount.adjustToRate(rate);
        assertEq(
            subscription.withdrawable(tokenId),
            (amount.toInternal(testToken.decimals()).adjustToRate(rate) - lockedAmount).toExternal(testToken.decimals()),
            "deposited amount partially locked"
        );
    }

    function testFlow(uint8 decimals) public {
        decimals = uint8(bound(decimals, 0, 64));

        currentTime = 100_000;
        uint256 amount = 10 * (10 ** decimals);

        createContracts(decimals);
        uint256 tokenId = mintToken(alice, amount);

        setCurrentTime(100_001);
        assertTrue(subscription.isActive(tokenId), "sub active");

        assertEq(103_333, subscription.expiresAt(tokenId), "sub expires after 3_333 blocks");

        setCurrentTime(102_001);

        assertEq(subscription.claimable(), (2_000 * rate).toExternal(decimals), "claimable");

        vm.startPrank(alice);
        testToken.approve(address(subscription), amount);
        subscription.renew(tokenId, amount, "");
        vm.stopPrank();

        assertEq(106_666, subscription.expiresAt(tokenId), "sub added another 3_333 blocks");

        setCurrentTime(200_000);
        assertFalse(subscription.isActive(tokenId), "sub expired");

        vm.startPrank(owner);
        uint256 claimable = subscription.claimable();
        assertEq(
            claimable,
            (amount * 2).toInternal(decimals).adjustToRate(rate).toExternal(decimals),
            "full sub amount claimable"
        );

        subscription.claim(owner);
        assertEq(testToken.balanceOf(owner), claimable, "claimable amount claimed");
    }

    function testFlow_withdraw(uint8 decimals) public {
        decimals = uint8(bound(decimals, 0, 64));

        currentTime = 100_000;
        uint256 amount = 10 * (10 ** decimals);

        createContracts(decimals);
        uint256 tokenId = mintToken(alice, amount);

        assertEq(subscription.claimable(), 0, "in beginning, nothing claimable");
        setCurrentTime(100_001);
        assertTrue(subscription.isActive(tokenId), "sub active");

        assertEq(103_333, subscription.expiresAt(tokenId), "sub expires after 3_333 blocks");

        setCurrentTime(102_000);

        uint256 withdrawable = subscription.withdrawable(tokenId);
        assertEq(withdrawable, (1_333 * rate).toExternal(decimals), "partial withdrawable");

        uint256 b = testToken.balanceOf(alice);
        vm.prank(alice);
        subscription.cancel(tokenId);
        assertEq(testToken.balanceOf(alice), b + (1_333 * rate).toExternal(decimals), "funds returned");
        assertEq(subscription.claimable(), (2_000 * rate).toExternal(decimals), "after cancel: remaining amount claimable");

        setCurrentTime(200_000);

        vm.startPrank(owner);
        uint256 claimable = subscription.claimable();
        assertEq(claimable, (2_000 * rate).toExternal(decimals), "claimable");

        subscription.claim(owner);
        assertEq(testToken.balanceOf(owner), claimable, "claimable amount claimed");
    }
}