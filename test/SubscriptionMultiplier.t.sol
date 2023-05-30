// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Subscription.sol";

import {SubscriptionEvents, ClaimEvents} from "../src/ISubscription.sol";
import {SubscriptionLib} from "../src/SubscriptionLib.sol";
import {Creator} from "../src/Creator.sol";

import {ERC20DecimalsMock} from "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SubscriptionMultiplierTest is Test, SubscriptionEvents, ClaimEvents {
    using SubscriptionLib for uint256;

    ERC1967Proxy public subscriptionProxy;
    Subscription public subscriptionImplementation;
    Subscription public subscription;
    ERC20DecimalsMock private testToken;
    Creator public creator;
    uint256 public rate;
    uint256 public lock;
    uint256 public epochSize;

    uint8 public decimals;

    address public owner;
    uint256 public ownerTokenId;
    address public alice;

    string public message;

    function setUp() public {
        owner = address(1);
        alice = address(10);

        message = "Hello World";

        rate = 3 ether / 1000; // 0.003 tokens per block
        lock = 100;
        epochSize = 100;
        decimals = 6;
        creator = new Creator();
        vm.prank(owner);
        ownerTokenId = creator.mint();

        testToken = new ERC20DecimalsMock("Test", "TEST", decimals);
        // init simple proxy setup
        subscriptionImplementation = new Subscription();
        subscriptionProxy = new ERC1967Proxy(
            address(subscriptionImplementation),
            ""
        );
        subscription = Subscription(address(subscriptionProxy));
        subscription.initialize(
            address(testToken),
            rate,
            lock,
            epochSize,
            address(creator),
            ownerTokenId
        );

        testToken.approve(address(subscription), type(uint256).max);

        testToken.mint(alice, UINT256_MAX);
    }

    function mintToken(
        address user,
        uint256 amount,
        uint256 multiplier
    ) private returns (uint256 tokenId) {
        uint256 mRate = (rate * multiplier) / subscription.MULTIPLIER_BASE();
        vm.startPrank(user);
        testToken.approve(address(subscription), amount);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(
            subscription.totalSupply() + 1,
            amount,
            amount.toInternal(testToken).adjustToRate(mRate),
            user,
            message
        );

        tokenId = subscription.mint(amount, multiplier, message);
        vm.stopPrank();
        assertEq(
            testToken.balanceOf(address(subscription)),
            amount,
            "amount send to subscription contract"
        );

        uint256 lockedAmount = (amount.toInternal(testToken) * lock) /
            subscription.LOCK_BASE();
        lockedAmount = lockedAmount.adjustToRate(mRate);
        assertEq(
            subscription.withdrawable(tokenId),
            (amount.toInternal(testToken).adjustToRate(mRate) - lockedAmount)
                .toExternal(testToken),
            "deposited amount partially locked"
        );
    }

    function testFlow(uint256 multiplier) public {
        multiplier = bound(multiplier, 100, 100_000);

        vm.roll(100_000);
        uint256 amount = (10 * (10**decimals) * multiplier) /
            subscription.MULTIPLIER_BASE();
        uint256 mRate = (rate * multiplier) / subscription.MULTIPLIER_BASE();

        uint256 tokenId = mintToken(alice, amount, multiplier);

        vm.roll(100_001);
        assertTrue(subscription.isActive(tokenId), "sub active");

        assertEq(
            103_333,
            subscription.expiresAt(tokenId),
            "sub expires after 3_333 blocks"
        );

        vm.roll(102_001);

        assertEq(
            subscription.claimable(),
            (2_000 * mRate).toExternal(testToken),
            "claimable"
        );

        vm.startPrank(alice);
        testToken.approve(address(subscription), amount);
        subscription.renew(tokenId, amount, "");
        vm.stopPrank();

        assertEq(
            106_666,
            subscription.expiresAt(tokenId),
            "sub added another 3_333 blocks"
        );

        vm.roll(200_000);
        assertFalse(subscription.isActive(tokenId), "sub expired");

        vm.startPrank(owner);
        uint256 claimable = subscription.claimable();
        assertEq(
            claimable,
            (amount * 2).toInternal(testToken).adjustToRate(mRate).toExternal(
                testToken
            ),
            "full sub amount claimable"
        );

        subscription.claim();
        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable amount claimed"
        );
    }

    function testFlow_withdraw(uint256 multiplier) public {
        multiplier = bound(multiplier, 100, 100_000);

        vm.roll(100_000);
        uint256 amount = (10 * (10**decimals) * multiplier) /
            subscription.MULTIPLIER_BASE();
        uint256 mRate = (rate * multiplier) / subscription.MULTIPLIER_BASE();

        uint256 tokenId = mintToken(alice, amount, multiplier);

        vm.roll(100_001);
        assertTrue(subscription.isActive(tokenId), "sub active");

        assertEq(
            103_333,
            subscription.expiresAt(tokenId),
            "sub expires after 3_333 blocks"
        );

        vm.roll(102_000);

        uint256 withdrawable = subscription.withdrawable(tokenId);
        assertEq(
            withdrawable,
            (1_333 * mRate).toExternal(testToken),
            "partial withdrawable"
        );

        uint256 b = testToken.balanceOf(alice);
        vm.prank(alice);
        subscription.cancel(tokenId);
        assertEq(
            testToken.balanceOf(alice),
            b + (1_333 * mRate).toExternal(testToken),
            "funds returned"
        );

        vm.roll(200_000);

        vm.startPrank(owner);
        uint256 claimable = subscription.claimable();
        assertEq(claimable, (2_000 * mRate).toExternal(testToken), "claimable");

        subscription.claim();
        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable amount claimed"
        );
    }
}