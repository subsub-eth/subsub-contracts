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

contract SubscriptionMultiplierTest is Test, SubscriptionEvents, ClaimEvents {
    using Lib for uint256;

    ERC1967Proxy public subscriptionProxy;
    TestSubscription public subscriptionImplementation;
    TestSubscription public subscription;
    ERC20DecimalsMock private testToken;
    SubscriptionHandle public handle;
    uint256 public rate;
    uint24 public lock;
    uint64 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    address public owner;
    uint256 public ownerTokenId;
    address public alice;

    string public message;

    MetadataStruct public metadata;
    SubSettings public settings;

    uint256 public currentTime;

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
        decimals = 6;

        handle = new SimpleSubscriptionHandle(address(0));

        testToken = new ERC20DecimalsMock(decimals);
        settings = SubSettings(testToken, rate, lock, epochSize, maxSupply);

        // init simple proxy setup
        subscriptionImplementation = new TestSubscription(address(handle));
        subscriptionProxy = new ERC1967Proxy(
            address(subscriptionImplementation),
            ""
        );
        subscription = TestSubscription(address(subscriptionProxy));
        setCurrentTime(1);
        subscription.initialize(
            "test",
            "test",
            metadata,
            settings
        );

        vm.prank(owner);
        handle.register(address(subscription));

        testToken.approve(address(subscription), type(uint256).max);

        testToken.mint(alice, UINT256_MAX);
    }

    function mintToken(
        address user,
        uint256 amount,
        uint24 multiplier
    ) private returns (uint256 tokenId) {
        uint256 mRate = (rate * multiplier) / Lib.MULTIPLIER_BASE;
        vm.startPrank(user);
        testToken.approve(address(subscription), amount);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(
            subscription.totalSupply() + 1,
            amount,
            amount.toInternal(testToken.decimals()).adjustToRate(mRate),
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

        uint256 lockedAmount = (amount.toInternal(testToken.decimals()) * lock) /
            subscription.LOCK_BASE();
        lockedAmount = lockedAmount.adjustToRate(mRate);
        assertEq(
            subscription.withdrawable(tokenId),
            (amount.toInternal(testToken.decimals()).adjustToRate(mRate) - lockedAmount)
                .toExternal(testToken.decimals()),
            "deposited amount partially locked"
        );
    }

    function testFlow(uint24 multiplier) public {
        multiplier = uint24(bound(multiplier, 100, 100_000));

        setCurrentTime(100_000);
        uint256 amount = (10 * (10**decimals) * multiplier) /
            Lib.MULTIPLIER_BASE;
        uint256 mRate = (rate * multiplier) / Lib.MULTIPLIER_BASE;

        uint256 tokenId = mintToken(alice, amount, multiplier);

        setCurrentTime(100_001);
        assertTrue(subscription.isActive(tokenId), "sub active");

        assertEq(
            103_333,
            subscription.expiresAt(tokenId),
            "sub expires after 3_333 blocks"
        );

        setCurrentTime(102_001);

        assertEq(
            subscription.claimable(),
            (2_000 * mRate).toExternal(testToken.decimals()),
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

        setCurrentTime(200_000);
        assertFalse(subscription.isActive(tokenId), "sub expired");

        vm.startPrank(owner);
        uint256 claimable = subscription.claimable();
        assertEq(
            claimable,
            (amount * 2).toInternal(testToken.decimals()).adjustToRate(mRate).toExternal(
                testToken.decimals()
            ),
            "full sub amount claimable"
        );

        subscription.claim(owner);
        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable amount claimed"
        );
    }

    function testFlow_withdraw(uint24 multiplier) public {
        multiplier = uint24(bound(multiplier, 100, 100_000));

        setCurrentTime(100_000);
        uint256 amount = (10 * (10**decimals) * multiplier) /
            Lib.MULTIPLIER_BASE;
        uint256 mRate = (rate * multiplier) / Lib.MULTIPLIER_BASE;

        uint256 tokenId = mintToken(alice, amount, multiplier);

        setCurrentTime(100_001);
        assertTrue(subscription.isActive(tokenId), "sub active");

        assertEq(
            103_333,
            subscription.expiresAt(tokenId),
            "sub expires after 3_333 blocks"
        );

        setCurrentTime(102_000);

        uint256 withdrawable = subscription.withdrawable(tokenId);
        assertEq(
            withdrawable,
            (1_333 * mRate).toExternal(testToken.decimals()),
            "partial withdrawable"
        );

        uint256 b = testToken.balanceOf(alice);
        vm.prank(alice);
        subscription.cancel(tokenId);
        assertEq(
            testToken.balanceOf(alice),
            b + (1_333 * mRate).toExternal(testToken.decimals()),
            "funds returned"
        );

        setCurrentTime(200_000);

        vm.startPrank(owner);
        uint256 claimable = subscription.claimable();
        assertEq(claimable, (2_000 * mRate).toExternal(testToken.decimals()), "claimable");

        subscription.claim(owner);
        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable amount claimed"
        );
    }
}