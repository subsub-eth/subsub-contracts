// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Subscription.sol";
import "../mocks/TestSubscription.sol";

import {
    SubscriptionEvents,
    ClaimEvents,
    MetadataStruct,
    SubSettings,
    SubscriptionFlags
} from "../../src/subscription/ISubscription.sol";
import "../../src/subscription/handle/SubscriptionHandle.sol";

import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// TODO test mint/renew with amount==0
// TODO test lock 0% and 100%
contract SubscriptionTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags {
    ERC1967Proxy public subscriptionProxy;
    TestSubscription public subscriptionImplementation;
    TestSubscription public subscription;
    ERC20DecimalsMock private testToken;
    SubscriptionHandle public handle;
    uint256 public rate;
    uint256 public lock;
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

    event MetadataUpdate(uint256 _tokenId);

    function setCurrentTime(uint64 newTime) internal {
        currentTime = newTime;
        subscription.setNow(newTime);
    }

    function setUp() public {
        owner = address(1);
        alice = address(10);
        bob = address(20);
        charlie = address(30);

        message = "Hello World";

        metadata = MetadataStruct("test", "test", "test");

        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;

        handle = new SimpleSubscriptionHandle(address(0));

        testToken = new ERC20DecimalsMock(18);
        settings = SubSettings(testToken, rate, lock, epochSize, maxSupply);

        // init simple proxy setup
        subscriptionImplementation = new TestSubscription(address(handle));
        subscriptionProxy = new ERC1967Proxy(
            address(subscriptionImplementation),
            ""
        );
        subscription = TestSubscription(address(subscriptionProxy));
        setCurrentTime(1);
        subscription.initialize("test", "test", metadata, settings);

        vm.prank(owner);
        handle.register(address(subscription));

        testToken.approve(address(subscription), type(uint256).max);

        testToken.mint(address(this), 1_000_000);
        testToken.mint(alice, 100_000);
        testToken.mint(bob, 20_000);
    }

    function createSubWithProxy() private returns (Subscription) {
        Subscription impl = new TestSubscription(address(handle));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        return Subscription(address(proxy));
    }

    function testConstruct_not0token() public {
        Subscription sub = createSubWithProxy();
        settings.token = ERC20DecimalsMock(address(0));
        settings.rate = 10;
        settings.lock = 0;
        settings.epochSize = 10;

        vm.expectRevert("SUB: token cannot be 0 address");
        sub.initialize("test", "test", metadata, settings);
    }

    function testConstruct_not0rate() public {
        Subscription sub = createSubWithProxy();
        settings.token = testToken;
        settings.rate = 0;
        settings.lock = 0;
        settings.epochSize = 10;
        vm.expectRevert("SUB: rate cannot be 0");
        sub.initialize("test", "test", metadata, settings);
    }

    function testConstruct_not0epochSize() public {
        Subscription sub = createSubWithProxy();
        settings.token = testToken;
        settings.rate = 10;
        settings.lock = 10_000;
        settings.epochSize = 0;
        vm.expectRevert("SUB: invalid epochSize");
        sub.initialize("test", "test", metadata, settings);
    }

    function testConstruct_lockTooLarge() public {
        Subscription sub = createSubWithProxy();
        settings.token = testToken;
        settings.rate = 10;
        settings.lock = 10_001;
        settings.epochSize = 10;
        vm.expectRevert("SUB: lock percentage out of range");
        sub.initialize("test", "test", metadata, settings);
    }

    function testSetExternalUrl() public {
        string memory url = "something else";
        vm.prank(owner);
        subscription.setExternalUrl(url);

        (,, string memory externalUrl) = subscription.metadata();

        assertEq(url, externalUrl);
    }

    function testSetExternalUrl_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        subscription.setExternalUrl("meh");
    }

    function testSetImage() public {
        string memory newImage = "something else";
        vm.prank(owner);
        subscription.setImage(newImage);

        (, string memory image,) = subscription.metadata();

        assertEq(newImage, image);
    }

    function testSetImage_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        subscription.setImage("meh");
    }

    function testSetDescription() public {
        string memory desc = "something else";
        vm.prank(owner);
        subscription.setDescription(desc);

        (string memory description,,) = subscription.metadata();

        assertEq(desc, description);
    }

    function testSetDescription_notOwner() public {
        string memory desc = "something else";
        vm.startPrank(alice);

        vm.expectRevert();
        subscription.setDescription(desc);
    }

    function mintToken(address user, uint256 amount) private returns (uint256 tokenId) {
        vm.startPrank(user);
        testToken.approve(address(subscription), amount);

        vm.expectEmit();
        emit SubscriptionRenewed(subscription.totalSupply() + 1, amount, (amount / rate) * rate, user, message);

        tokenId = subscription.mint(amount, 100, message);
        vm.stopPrank();
        assertEq(testToken.balanceOf(address(subscription)), amount, "amount send to subscription contract");

        uint256 lockedAmount = (amount * lock) / subscription.LOCK_BASE();
        lockedAmount = (lockedAmount / rate) * rate;
        assertEq(
            subscription.withdrawable(tokenId),
            (amount / rate) * rate - lockedAmount,
            "deposited amount partially locked"
        );
    }

    function testMint() public {
        uint256 tokenId = mintToken(alice, 100);

        bool active = subscription.isActive(tokenId);
        uint256 end = subscription.expiresAt(tokenId);

        assertEq(tokenId, 1, "subscription has first token id");
        assertEq(end, currentTime + 20, "subscription ends at 20");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
        assertTrue(active, "subscription active");
    }

    function testMint_multiplierTooSmall() public {
        vm.expectRevert("SUB: multiplier invalid");
        subscription.mint(0, 99, "");
    }

    function testMint_multiplierTooLarge() public {
        vm.expectRevert("SUB: multiplier invalid");
        subscription.mint(0, 100_001, "");
    }

    function testMint_zeroAmount() public {
        uint256 tokenId = mintToken(alice, 0);

        bool active = subscription.isActive(tokenId);
        uint256 end = subscription.expiresAt(tokenId);

        assertEq(tokenId, 1, "subscription has first token id");
        assertEq(end, currentTime, "subscription ends at current block");
        assertEq(subscription.deposited(tokenId), 0, "0 tokens deposited");
        assertFalse(active, "subscription active");
    }

    function testMint_whenPaused() public {
        vm.prank(owner);
        subscription.setFlags(MINTING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        subscription.mint(1, 100, "");

        vm.prank(owner);
        subscription.setFlags(0);

        mintToken(alice, 100);
    }

    function testMaxSupply() public {
        Subscription sub = createSubWithProxy();
        settings.maxSupply = 1;
        sub.initialize("test", "test", metadata, settings);

        assertEq(0, sub.totalSupply());

        vm.startPrank(alice);
        sub.mint(0, 100, "");

        assertEq(1, sub.totalSupply());

        vm.expectRevert("SUB: max supply reached");
        sub.mint(0, 100, "");
    }

    function testMaxSupply_none() public {
        Subscription sub = createSubWithProxy();
        settings.maxSupply = 0;
        sub.initialize("test", "test", metadata, settings);

        vm.startPrank(alice);
        vm.expectRevert("SUB: max supply reached");
        sub.mint(0, 100, "");
    }

    function testMaxSupply_withBurn() public {
        Subscription sub = createSubWithProxy();
        settings.maxSupply = 1;
        sub.initialize("test", "test", metadata, settings);

        assertEq(0, sub.totalSupply());

        vm.startPrank(alice);
        uint256 tokenId = sub.mint(0, 100, "");
        assertEq(1, sub.totalSupply());

        sub.burn(tokenId);
        assertEq(0, sub.totalSupply());

        sub.mint(0, 100, "");
        assertEq(1, sub.totalSupply());

        vm.expectRevert("SUB: max supply reached");
        sub.mint(0, 100, "");
    }

    function testBurn() public {
        uint256 amount = 100;
        uint256 tokenId = mintToken(alice, amount);

        assertEq(subscription.totalSupply(), 1, "only one sub exists");

        assertEq(testToken.balanceOf(address(subscription)), amount, "sub contract has tokens");

        vm.prank(alice);
        subscription.burn(tokenId);

        assertEq(subscription.totalSupply(), 0, "no subs exist");
        assertEq(testToken.balanceOf(address(subscription)), amount, "sub contract still has tokens");
        assertEq(subscription.balanceOf(alice), 0, "alice does not own any subs anymore");

        // bahhhh
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = subscription.getSubData(tokenId);

        assertEq(0, a);
        assertEq(0, b);
        assertEq(0, c);
        assertEq(0, d);
        assertEq(0, e);
        assertEq(0, f);

        vm.startPrank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.deposited(tokenId);
    }

    function testBurn_nonExisting() public {
        vm.expectRevert("SUB: not the owner");
        subscription.burn(123123);
    }

    function testBurn_notTwice() public {
        uint256 tokenId = mintToken(alice, 0);

        vm.startPrank(alice);
        subscription.burn(tokenId);

        vm.expectRevert("SUB: not the owner");
        subscription.burn(tokenId);
    }

    function testBurn_notOwner() public {
        uint256 tokenId = mintToken(alice, 0);

        vm.startPrank(bob);
        vm.expectRevert("SUB: not the owner");
        subscription.burn(tokenId);
    }

    function testIsActive() public {
        uint256 tokenId = mintToken(alice, 100);

        assertEq(tokenId, 1, "subscription has first token id");

        // fast forward
        setCurrentTime(currentTime + 5);
        bool active = subscription.isActive(tokenId);

        assertTrue(active, "subscription active");
    }

    function testIsActive_lastBlock() public {
        uint256 tokenId = mintToken(alice, 100);

        assertEq(tokenId, 1, "subscription has first token id");

        // fast forward
        setCurrentTime(currentTime + 19);
        bool active = subscription.isActive(tokenId);

        assertTrue(active, "subscription active");

        setCurrentTime(currentTime + 1); // + 20
        active = subscription.isActive(tokenId);

        assertFalse(active, "subscription inactive");
    }

    function testRenew() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(initialEnd, currentTime + 2000, "subscription initially ends at 2000");
        assertEq(subscription.deposited(tokenId), initialDeposit, "10_000 tokens deposited");

        // fast forward
        setCurrentTime(currentTime + 5);

        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, 20_000, 30_000, address(this), message);

        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        assertFalse(subscription.flagsEnabled(RENEWAL_PAUSED), "contract is not paused");

        subscription.renew(tokenId, 20_000, message);

        assertEq(testToken.balanceOf(address(subscription)), 30_000, "all tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + 4_000, "subscription expires at 6000");
        assertEq(subscription.deposited(tokenId), 30_000, "30000 tokens deposited");

        uint256 fundsUsed = 5 * rate;
        uint256 lockedAmount = ((((30_000 - fundsUsed) * lock) / subscription.LOCK_BASE()) / rate) * rate;
        assertEq(
            subscription.withdrawable(tokenId), 29975 - lockedAmount, "Locked amount updated to 29975 - 295 = 29680"
        );
    }

    function testRenew_whenPaused() public {
        uint256 tokenId = mintToken(alice, 100);

        // fast forward
        setCurrentTime(currentTime + 5);

        vm.prank(owner);
        subscription.setFlags(RENEWAL_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        subscription.renew(tokenId, 100, "");
    }

    function testRenew_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.renew(tokenId, 200, message);

        assertEq(testToken.balanceOf(address(subscription)), 0, "no tokens sent");
    }

    function testRenew_zeroAmount() public {
        uint256 tokenId = mintToken(alice, 0);

        vm.expectRevert("SUB: amount too small");
        subscription.renew(tokenId, 0, "too small");
    }

    function testRenew_minAmount() public {
        uint256 tokenId = mintToken(alice, 0);

        subscription.renew(tokenId, rate, "just right");

        assertEq(subscription.deposited(tokenId), rate, "min renewal");

        vm.expectRevert("SUB: amount too small");
        subscription.renew(tokenId, rate - 1, "too small");
    }

    function testRenew_afterMint() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(initialEnd, currentTime + 20, "subscription initially ends at 20");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(testToken.balanceOf(address(subscription)), 300, "all tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + 40, "subscription ends at 60");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_inActive() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(initialEnd, currentTime + 20, "subscription initially ends at 20");

        // fast forward
        uint64 ff = 50;
        setCurrentTime(currentTime + ff);
        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(testToken.balanceOf(address(subscription)), 300, "all tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, currentTime + 40, "subscription ends at 90");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_notOwner() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(initialEnd, currentTime + 20, "subscription initially ends at 20");

        uint256 amount = 200;
        vm.startPrank(bob);

        testToken.approve(address(subscription), amount);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, bob, message);

        subscription.renew(tokenId, amount, message);

        vm.stopPrank();

        assertEq(testToken.balanceOf(address(subscription)), 300, "all tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + (amount / rate), "subscription end extended");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testWithdrawable() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit - ((initialDeposit * lock) / subscription.LOCK_BASE()),
            "withdrawable deposit 9900"
        );

        uint64 passed = 50;

        setCurrentTime(currentTime + passed);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(subscription.withdrawable(tokenId), initialDeposit - (passed * rate), "withdrawable deposit 750");
        assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
        assertEq(subscription.deposited(tokenId), initialDeposit, "10000 tokens deposited");
    }

    function testWithdrawable_smallDeposit() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId), initialDeposit, "withdrawable deposit 100 as the deposit is too low"
        );

        uint64 passed = 5;

        setCurrentTime(currentTime + passed);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(subscription.withdrawable(tokenId), initialDeposit - (passed * rate), "withdrawable deposit 75");
        assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
        assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    }

    function testWithdrawable_locked() public {
        uint256 initialDeposit = 1234;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.startPrank(alice);
        testToken.approve(address(subscription), type(uint256).max);

        // 1234 * 1% => 12 => 10
        assertEq(subscription.withdrawable(tokenId), 1230 - 10);

        uint256 newAmount = 321;
        subscription.renew(tokenId, newAmount, "");

        assertEq(subscription.withdrawable(tokenId), 1230 + 320 - 15);
    }

    function testWithdrawable_inActive() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint64 passed = 50;

        setCurrentTime(currentTime + passed);

        assertFalse(subscription.isActive(tokenId), "subscription inactive");
        assertEq(subscription.withdrawable(tokenId), 0, "withdrawable deposit 0");
        assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    }

    function testWithdraw1() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        uint64 passed = 5;
        setCurrentTime(currentTime + passed);

        // try withdraw 0 without effect
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, 0, 100);

        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        vm.prank(alice);
        subscription.withdraw(tokenId, 0);

        uint256 aliceBalance = testToken.balanceOf(alice);
        uint256 subBalance = testToken.balanceOf(address(subscription));
        uint256 withdrawable = subscription.withdrawable(tokenId);

        uint256 amount = 25;

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, 25, 75);

        vm.prank(alice);
        subscription.withdraw(tokenId, amount);

        assertEq(testToken.balanceOf(alice), aliceBalance + amount, "funds withdrawn to alice");
        assertEq(testToken.balanceOf(address(subscription)), subBalance - amount, "funds withdrawn from contract");
        assertEq(subscription.withdrawable(tokenId), withdrawable - amount, "withdrawable amount reduced");

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        assertEq(subscription.deposited(tokenId), initialDeposit - amount, "75 tokens deposited");
    }

    function testWithdraw_operator() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        // approve operator
        vm.prank(alice);
        subscription.setApprovalForAll(bob, true);

        uint64 passed = 5;
        setCurrentTime(currentTime + passed);

        uint256 bobBalance = testToken.balanceOf(bob);

        uint256 amount = 25;

        vm.prank(bob);
        subscription.withdraw(tokenId, amount);

        assertEq(bobBalance + amount, testToken.balanceOf(bob), "operator withdrew funds");
    }

    function testWithdraw_approved() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        // approve operator
        vm.prank(alice);
        subscription.approve(bob, tokenId);

        uint64 passed = 5;
        setCurrentTime(currentTime + passed);

        uint256 bobBalance = testToken.balanceOf(bob);

        uint256 amount = 25;

        vm.prank(bob);
        subscription.withdraw(tokenId, amount);

        assertEq(bobBalance + amount, testToken.balanceOf(bob), "approved account withdrew funds");
    }

    function testWithdraw_all() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint64 passed = 5;
        setCurrentTime(currentTime + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);
        uint256 withdrawable = subscription.withdrawable(tokenId);

        uint256 amount = withdrawable;

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);

        vm.prank(alice);
        subscription.withdraw(tokenId, amount);

        assertEq(
            testToken.balanceOf(alice),
            aliceBalance + initialDeposit - (passed * rate),
            "alice only reduced by 'used' amount"
        );
        assertEq(testToken.balanceOf(address(subscription)), passed * rate, "contract only contains 'used' amount");
        assertEq(subscription.withdrawable(tokenId), 0, "withdrawable amount is 0");

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(subscription.deposited(tokenId), initialDeposit - amount, "25 tokens deposited");
    }

    function testWithdraw_allAfterMint() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(subscription.deposited(tokenId), initialDeposit, "10000 tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");

        vm.prank(alice);
        vm.expectRevert("SUB: amount exceeds withdrawable");
        subscription.withdraw(tokenId, initialDeposit);
        assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
        assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    }

    function testWithdraw_allAfterMint_lowAmount() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");

        vm.prank(alice);
        subscription.withdraw(tokenId, initialDeposit);
        assertEq(testToken.balanceOf(address(subscription)), 0, "all tokens withdrawn");
        assertEq(subscription.deposited(tokenId), 0, "all tokens withdrawn");
    }

    function testWithdraw_revert_nonExisting() public {
        uint256 tokenId = 1000;

        vm.prank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.withdraw(tokenId, 10000);
    }

    function testWithdraw_revert_notOwner() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.prank(bob);
        vm.expectRevert("ERC721: caller is not token owner or approved");
        subscription.withdraw(tokenId, 10000);
        assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
        assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    }

    function testWithdraw_revert_largerAmount() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.prank(alice);
        vm.expectRevert("SUB: amount exceeds withdrawable");
        subscription.withdraw(tokenId, initialDeposit + 1);
        assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
        assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    }

    function testCancel() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint64 passed = 5;
        setCurrentTime(currentTime + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);

        uint256 amount = initialDeposit - passed * rate;

        assertEq(subscription.withdrawable(tokenId), amount, "withdrawable amount is 75");

        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);

        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        vm.prank(alice);
        subscription.cancel(tokenId);

        assertEq(testToken.balanceOf(alice), aliceBalance + amount, "alice only reduced by 'used' amount");
        assertEq(
            testToken.balanceOf(address(subscription)), initialDeposit - amount, "contract only contains 'used' amount"
        );
        assertEq(subscription.withdrawable(tokenId), 0, "withdrawable amount is 0");

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(subscription.deposited(tokenId), initialDeposit - amount, "25 tokens deposited");
    }

    function testCancel_afterMint() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(subscription.deposited(tokenId), initialDeposit, "10000 tokens deposited");

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        assertEq(subscription.withdrawable(tokenId), 9900, "9900 tokens withdrawable due to lock");

        vm.prank(alice);
        subscription.cancel(tokenId);
        assertEq(testToken.balanceOf(address(subscription)), 100, "token balance not changed");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    }

    function testCancel_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.prank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.cancel(tokenId);
        assertEq(testToken.balanceOf(address(subscription)), 0, "token balance not changed");
    }

    function testSpent() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(subscription.spent(tokenId), 0, "nothing spent yet");

        setCurrentTime(currentTime + 1);

        assertEq(subscription.spent(tokenId), rate, "1 block spent");

        setCurrentTime(currentTime + 9);

        assertEq(subscription.spent(tokenId), 10 * rate, "10 block spent");

        setCurrentTime(currentTime + 1_000);

        assertEq(subscription.spent(tokenId), initialDeposit, "initial funds spent");
        assertEq(subscription.spent(tokenId), subscription.deposited(tokenId), "all deposited funds spent");
    }

    function testSpent_nonExisting() public {
        uint256 tokenId = 1234;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.spent(tokenId);
    }

    function testUnspent() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(subscription.unspent(tokenId), 100, "All funds are still unspent");

        setCurrentTime(currentTime + 1);

        assertEq(subscription.unspent(tokenId), 100 - rate, "1 block was spent");

        setCurrentTime(currentTime + 9);

        assertEq(subscription.unspent(tokenId), 100 - 10 * rate, "10 blocks were spent");

        setCurrentTime(currentTime + 1_000);

        assertEq(subscription.unspent(tokenId), 0, "no funds are unspent");
    }

    function testUnspent_nonExisting() public {
        uint256 tokenId = 1234;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.unspent(tokenId);
    }

    function testClaimable() public {
        mintToken(alice, 1_000);

        setCurrentTime(currentTime + (epochSize * 2));

        // partial epoch + complete epoch
        assertEq(subscription.claimable(), 9 * rate + epochSize * rate, "claimable partial epoch");
    }

    function testClaimable_instantly() public {
        setCurrentTime(10_000);
        mintToken(alice, 1_000);

        assertEq(subscription.claimable(), 0, "0 of deposit is instantly claimable");
    }

    function testClaimable_epoch0() public {
        mintToken(alice, 1_000);

        uint256 diff = epochSize - currentTime;
        setCurrentTime(currentTime + (epochSize * 1));

        // claim only epoch 0
        assertEq(subscription.claimable(), rate * diff, "partial funds of epoch 0 claimable");
    }

    function testClaimable_expiring() public {
        uint256 tokenId = mintToken(alice, 100);

        setCurrentTime(currentTime + (epochSize * 3));

        assertFalse(subscription.isActive(tokenId), "Subscription inactive");
        assertEq(subscription.claimable(), 100, "all funds claimable");
    }

    function testClaimable_tips() public {
        uint256 initAmount = 1_000;
        uint256 tokenId = mintToken(alice, initAmount);
        uint256 tipAmount = 100_000;

        subscription.tip(tokenId, tipAmount, "");

        assertEq(subscription.claimableTips(), tipAmount, "tipped funds claimable");

        setCurrentTime(currentTime + (epochSize * 300));

        assertEq(subscription.claimable() + subscription.claimableTips(),
                 tipAmount + initAmount, "all funds claimable");
    }

    function testClaim() public {
        uint256 tokenId = mintToken(alice, 1_000);

        assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
        setCurrentTime(currentTime + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        assertEq(claimable, 9 * rate + epochSize * rate, "claimable partial epoch");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, claimable);

        vm.prank(owner);
        subscription.claim(owner);

        assertEq(testToken.balanceOf(owner), claimable, "claimable funds transferred to owner");
        assertEq(subscription.activeSubShares(), 1 * Lib.MULTIPLIER_BASE, "subscriptions updated");

        assertEq(subscription.claimable(), 0, "no funds claimable right after claim");

        assertEq(subscription.deposited(tokenId), 1_000, "1000 tokens deposited");
    }

    function testClaim_otherAccount() public {
        mintToken(alice, 1_000);

        assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
        setCurrentTime(currentTime + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        assertEq(claimable, 9 * rate + epochSize * rate, "claimable partial epoch");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, claimable);

        vm.prank(owner);
        subscription.claim(charlie);

        assertEq(testToken.balanceOf(charlie), claimable, "claimable funds transferred to charlie");
    }

    function testClaim_instantly() public {
        setCurrentTime(10_000);

        uint256 tokenId = mintToken(alice, 1_000);

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();

        assertEq(claimable, 0, "no funds claimable right after claim");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, claimable);

        vm.prank(owner);
        subscription.claim(owner);

        assertEq(testToken.balanceOf(owner), claimable, "claimable funds transferred to owner");
        assertEq(subscription.activeSubShares(), 100, "active subscriptions stay visible until epoch ends");

        assertEq(subscription.deposited(tokenId), 1_000, "1000 tokens deposited");
    }

    function testClaim_onlyOwner() public {
        vm.expectRevert();
        subscription.claim(owner);
    }

    function testClaim_nextEpoch() public {
        uint256 tokenId = mintToken(alice, 1_000);

        assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
        setCurrentTime(currentTime + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        uint256 totalClaimed = claimable;
        assertEq(claimable, 9 * rate + epochSize * rate, "claimable partial epoch");
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, totalClaimed);

        vm.prank(owner);
        subscription.claim(owner);

        uint256 ownerBalance = testToken.balanceOf(owner);
        assertEq(ownerBalance, claimable, "claimable funds transferred to owner");
        assertEq(subscription.activeSubShares(), 1 * Lib.MULTIPLIER_BASE, "subscriptions updated");

        assertEq(subscription.claimable(), 0, "no funds claimable right after claim");

        setCurrentTime(currentTime + (epochSize));
        claimable = subscription.claimable();
        totalClaimed += claimable;
        assertEq(claimable, epochSize * rate, "new epoch claimable");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, totalClaimed);

        vm.prank(owner);
        subscription.claim(owner);

        assertEq(testToken.balanceOf(owner), ownerBalance + claimable, "new funds transferred to owner");
        assertEq(subscription.activeSubShares(), 1 * Lib.MULTIPLIER_BASE, "subscriptions updated");

        assertEq(subscription.deposited(tokenId), 1_000, "1000 tokens deposited");
    }

    function testClaim_expired() public {
        uint256 funds = 100;
        uint256 tokenId = mintToken(alice, funds);

        assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
        setCurrentTime(currentTime + (epochSize * 3));

        assertFalse(subscription.isActive(tokenId), "Subscription inactive");
        assertEq(subscription.claimable(), funds, "all funds claimable");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(funds, funds);

        vm.prank(owner);
        subscription.claim(owner);

        assertEq(testToken.balanceOf(owner), funds, "all funds transferred to owner");

        assertEq(subscription.activeSubShares(), 0, "active subs updated");
        assertEq(subscription.claimable(), 0, "no funds claimable right after claim");

        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    }

    function testClaim_tips() public {
        setCurrentTime(currentTime + (epochSize * 300));

        uint256 initAmount = 1_000;
        uint256 tokenId = mintToken(alice, initAmount);
        uint256 tipAmount = 100_000;

        subscription.tip(tokenId, tipAmount, "");

        assertEq(testToken.balanceOf(address(subscription)), initAmount + tipAmount, "amount in sub contract");

        vm.prank(owner);
        subscription.claim(owner);

        assertEq(testToken.balanceOf(owner), tipAmount, "tips claimed");
        assertEq(testToken.balanceOf(address(subscription)), initAmount, "sub deposit remains");

        vm.prank(owner);
        subscription.claim(owner);
        assertEq(testToken.balanceOf(owner), tipAmount, "no additional funds added on 2nd claim");
        assertEq(testToken.balanceOf(address(subscription)), initAmount, "no funds transfered on 2nd claim");
    }

    function testFuzz_SetUnsetFlags(uint256 flags) public {
        flags = bound(flags, 1, ALL_FLAGS);
        vm.prank(owner);
        subscription.setFlags(flags);
        assertTrue(subscription.flagsEnabled(flags), "flags set");

        vm.prank(owner);
        subscription.setFlags(0);
        assertFalse(subscription.flagsEnabled(flags), "flags not set");
    }

    function testSetFlags_invalid() public {
        vm.startPrank(owner);
        vm.expectRevert("SUB: invalid settings");
        subscription.setFlags(ALL_FLAGS + 1);
    }

    function testSetFlags_notOwner() public {
        vm.expectRevert();
        subscription.setFlags(0x1);
    }

    function testTip() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 amount = 100;
        uint256 tokenBalance = 200;
        vm.startPrank(alice);

        testToken.approve(address(subscription), amount);

        assertEq(subscription.tips(tokenId), 0, "no tips in sub yet");

        vm.expectEmit();
        emit Tipped(tokenId, amount, amount, alice, "hello world");

        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        subscription.tip(tokenId, amount, "hello world");

        assertEq(subscription.deposited(tokenId), 100, "deposit stays the same");
        assertEq(subscription.tips(tokenId), 100, "tips increased by sent amount");
        assertEq(testToken.balanceOf(address(subscription)), tokenBalance, "funds transferred");
        vm.stopPrank();

        // tip from 'random' account
        amount = 200;
        tokenBalance = 400;

        vm.expectEmit();
        emit Tipped(tokenId, amount, 300, address(this), "hello world");

        subscription.tip(tokenId, amount, "hello world");
        assertEq(subscription.deposited(tokenId), 100, "deposit still the same");
        assertEq(subscription.tips(tokenId), 300, "tips increased by new sent amount");
        assertEq(testToken.balanceOf(address(subscription)), tokenBalance, "funds transferred 2");
    }

    function testTip_nonExisiting() public {
        uint256 tokenId = 1234;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.tip(tokenId, 1, "bla");
    }

    function testTip_zeroAmount() public {
        uint256 tokenId = mintToken(alice, 100);

        vm.expectRevert("SUB: amount too small");
        subscription.tip(tokenId, 0, "bla");
    }

    function testTip_minAmount() public {
        uint256 tokenId = mintToken(alice, 0);

        subscription.tip(tokenId, 1, "min amount");
        assertEq(subscription.tips(tokenId), 1, "min amount of tips deposited");
    }

    function testTip_whenPaused() public {
        uint256 tokenId = mintToken(alice, 100);

        vm.prank(owner);
        subscription.setFlags(TIPPING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        subscription.tip(tokenId, 100, "");
    }
}