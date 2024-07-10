// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Subscription.sol";
import "../mocks/TestSubscription.sol";
import "./AbstractTestSub.sol";

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

contract SubscriptionTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags, TestSubEvents {
    event MetadataUpdate(uint256 _tokenId);

    Subscription public sub;

    address public owner;
    address public alice;

    ERC20DecimalsMock public testToken;

    MetadataStruct public metadata;
    SubSettings public settings;
    uint256 public rate;
    uint24 public lock;
    uint64 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    function setUp() public {
        owner = address(10);
        alice = address(11);
        metadata = MetadataStruct("description", "image", "externalUrl");
        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;
        decimals = 12;

        testToken = new ERC20DecimalsMock(decimals);
        testToken.mint(alice, 10_000_000_000 ether);

        settings = SubSettings(testToken, rate, lock, epochSize, maxSupply);

        sub = new SimpleTestSub(owner, "name", "symbol", metadata, settings);
    }

    function testSetExternalUrl() public {
        string memory url = "something else";
        vm.prank(owner);
        sub.setExternalUrl(url);

        (,, string memory externalUrl) = sub.metadata();

        assertEq(url, externalUrl);
    }

    function testSetExternalUrl_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setExternalUrl("meh");
    }

    function testSetImage() public {
        string memory newImage = "something else";
        vm.prank(owner);
        sub.setImage(newImage);

        (, string memory image,) = sub.metadata();

        assertEq(newImage, image);
    }

    function testSetImage_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setImage("meh");
    }

    function testSetDescription() public {
        string memory desc = "something else";
        vm.prank(owner);
        sub.setDescription(desc);

        (string memory description,,) = sub.metadata();

        assertEq(desc, description);
    }

    function testSetDescription_notOwner() public {
        string memory desc = "something else";
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setDescription(desc);
    }

    function testSetFlags(uint256 flags) public {
        flags = bound(flags, 0, ALL_FLAGS);
        vm.prank(owner);
        sub.setFlags(flags);
    }

    function testSetFlags_invalid(uint256 flags) public {
        flags = bound(flags, ALL_FLAGS + 1, type(uint256).max);
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setFlags(flags);
    }

    function testSetFlags_notOwner() public {
        uint256 flags = 1;
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setFlags(flags);
    }

    // TODO check that no payment tokens are being transferred
    function testBurn(uint256 tokenId) public {
        BurnSub _sub = new BurnSub();

        _sub.simpleMint(alice, tokenId);

        assertEq(_sub.totalSupply(), 1, "Token created");
        assertEq(_sub.balanceOf(alice), 1, "Token created to user");

        vm.prank(alice);
        vm.expectEmit();
        emit Burned(tokenId);

        _sub.burn(tokenId);

        assertEq(_sub.totalSupply(), 0, "Token burned");
        assertEq(_sub.balanceOf(alice), 0, "Token burned from user");
    }

    function testBurn_notOwner(uint256 tokenId, address user) public {
        vm.assume(alice != user && user != address(this));
        BurnSub _sub = new BurnSub();

        _sub.simpleMint(alice, tokenId);

        assertEq(_sub.balanceOf(alice), 1, "Token created to user");

        vm.startPrank(user);
        vm.expectRevert();
        _sub.burn(tokenId);
    }

    function testBurn_twice(uint256 tokenId) public {
        BurnSub _sub = new BurnSub();

        _sub.simpleMint(alice, tokenId);

        vm.prank(alice);

        _sub.burn(tokenId);

        vm.expectRevert();
        _sub.burn(tokenId);
    }

    function testMint(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100, 100_000));

        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);

        vm.expectEmit();
        emit SubCreated(1, amount * _sub.CONV(), multiplier);
        vm.expectEmit();
        emit AddedToEpochs(amount * _sub.CONV(), multiplier, rate);
        vm.expectEmit();
        emit SubscriptionRenewed(1, amount, _sub.TOTAL_DEPOSITED(), alice, message);

        _sub.mint(amount, multiplier, message);

        assertEq(_sub.balanceOf(alice), 1, "Token created");
        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testMint_maxSupply(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100, 100_000));

        settings.maxSupply = 1;
        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        _sub.mint(amount, multiplier, message);

        vm.expectRevert("SUB: max supply reached");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_maxSupply0(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100, 100_000));

        settings.maxSupply = 0;
        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);
        vm.expectRevert("SUB: max supply reached");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_invalidMultiplier(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 0, 99));

        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_invalidMultiplier_large(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100_001, type(uint24).max));

        MintSub _sub = new MintSub(owner, settings);

        vm.startPrank(alice);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_mintPaused(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100_001, type(uint24).max));

        MintSub _sub = new MintSub(owner, settings);
        vm.prank(owner);
        _sub.setFlags(MINTING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        _sub.mint(amount, multiplier, message);
    }

    function testRenew(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));

        RenewExtendSub _sub = new RenewExtendSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, _sub.TOTAL_DEPOSITED(), alice, message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_reactivate(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));

        RenewReactivateSub _sub = new RenewReactivateSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsAdded(_sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, _sub.TOTAL_DEPOSITED(), alice, message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_otherUser(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        vm.assume(user != alice && user != address(this));

        testToken.mint(user, 100_000_000_000 ether);
        amount = bound(amount, 0, testToken.balanceOf(user));

        RenewExtendSub _sub = new RenewExtendSub(owner, settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, _sub.TOTAL_DEPOSITED(), user, message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_noToken(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        RenewExtendSub _sub = new RenewExtendSub(owner, settings);

        vm.startPrank(user);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.renew(tokenId, amount, message);
    }

    function testRenew_paused(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        RenewExtendSub _sub = new RenewExtendSub(owner, settings);

        vm.prank(owner);
        _sub.setFlags(RENEWAL_PAUSED);

        vm.startPrank(user);

        vm.expectRevert("Flag: setting enabled");
        _sub.renew(tokenId, amount, message);
    }

    // ERC1967Proxy public subscriptionProxy;
    // TestSubscription public subscriptionImplementation;
    // TestSubscription public subscription;
    // ERC20DecimalsMock private testToken;
    // SubscriptionHandle public handle;
    // uint256 public rate;
    // uint24 public lock;
    // uint64 public epochSize;
    // uint256 public maxSupply;
    //
    // address public owner;
    // uint256 public ownerTokenId;
    // address public alice;
    // address public bob;
    // address public charlie;
    //
    // string public message;
    //
    // MetadataStruct public metadata;
    // SubSettings public settings;
    //
    // uint64 public currentTime;
    //
    // event MetadataUpdate(uint256 _tokenId);
    //
    // function setCurrentTime(uint64 newTime) internal {
    //     currentTime = newTime;
    //     subscription.setNow(newTime);
    // }
    //
    // function setUp() public {
    //     owner = address(1);
    //     alice = address(10);
    //     bob = address(20);
    //     charlie = address(30);
    //
    //     message = "Hello World";
    //
    //     metadata = MetadataStruct("test", "test", "test");
    //
    //     rate = 5;
    //     lock = 100;
    //     epochSize = 10;
    //     maxSupply = 10_000;
    //
    //     handle = new SimpleSubscriptionHandle(address(0));
    //
    //     testToken = new ERC20DecimalsMock(18);
    //     settings = SubSettings(testToken, rate, lock, epochSize, maxSupply);
    //
    //     // init simple proxy setup
    //     subscriptionImplementation = new TestSubscription(address(handle));
    //     subscriptionProxy = new ERC1967Proxy(address(subscriptionImplementation), "");
    //     subscription = TestSubscription(address(subscriptionProxy));
    //     setCurrentTime(1);
    //     subscription.initialize("test", "test", metadata, settings);
    //
    //     vm.prank(owner);
    //     handle.register(address(subscription));
    //
    //     testToken.approve(address(subscription), type(uint256).max);
    //
    //     testToken.mint(address(this), 1_000_000);
    //     testToken.mint(alice, 100_000);
    //     testToken.mint(bob, 20_000);
    // }
    //
    //
    //
    // function testWithdrawable() public {
    //     uint256 initialDeposit = 10_000;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription active");
    //     assertEq(
    //         subscription.withdrawable(tokenId),
    //         initialDeposit - ((initialDeposit * lock) / Lib.LOCK_BASE),
    //         "withdrawable deposit 9900"
    //     );
    //
    //     uint64 passed = 50;
    //
    //     setCurrentTime(currentTime + passed);
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription active");
    //     assertEq(subscription.withdrawable(tokenId), initialDeposit - (passed * rate), "withdrawable deposit 750");
    //     assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "10000 tokens deposited");
    // }
    //
    // function testWithdrawable_smallDeposit() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription active");
    //     assertEq(
    //         subscription.withdrawable(tokenId), initialDeposit, "withdrawable deposit 100 as the deposit is too low"
    //     );
    //
    //     uint64 passed = 5;
    //
    //     setCurrentTime(currentTime + passed);
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription active");
    //     assertEq(subscription.withdrawable(tokenId), initialDeposit - (passed * rate), "withdrawable deposit 75");
    //     assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    // }
    //
    // function testWithdrawable_locked() public {
    //     uint256 initialDeposit = 1234;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     vm.startPrank(alice);
    //     testToken.approve(address(subscription), type(uint256).max);
    //
    //     // 1234 * 1% => 12 => 10
    //     assertEq(subscription.withdrawable(tokenId), 1230 - 10);
    //
    //     uint256 newAmount = 321;
    //     subscription.renew(tokenId, newAmount, "");
    //
    //     assertEq(subscription.withdrawable(tokenId), 1230 + 320 - 15);
    // }
    //
    // function testWithdrawable_inActive() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     uint64 passed = 50;
    //
    //     setCurrentTime(currentTime + passed);
    //
    //     assertFalse(subscription.isActive(tokenId), "subscription inactive");
    //     assertEq(subscription.withdrawable(tokenId), 0, "withdrawable deposit 0");
    //     assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    // }
    //
    // function testWithdraw1() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //     assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    //
    //     uint64 passed = 5;
    //     setCurrentTime(currentTime + passed);
    //
    //     // try withdraw 0 without effect
    //     vm.expectEmit();
    //     emit SubscriptionWithdrawn(tokenId, 0, 100);
    //
    //     vm.expectEmit();
    //     emit MetadataUpdate(tokenId);
    //
    //     vm.prank(alice);
    //     subscription.withdraw(tokenId, 0);
    //
    //     uint256 aliceBalance = testToken.balanceOf(alice);
    //     uint256 subBalance = testToken.balanceOf(address(subscription));
    //     uint256 withdrawable = subscription.withdrawable(tokenId);
    //
    //     uint256 amount = 25;
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit SubscriptionWithdrawn(tokenId, 25, 75);
    //
    //     vm.prank(alice);
    //     subscription.withdraw(tokenId, amount);
    //
    //     assertEq(testToken.balanceOf(alice), aliceBalance + amount, "funds withdrawn to alice");
    //     assertEq(testToken.balanceOf(address(subscription)), subBalance - amount, "funds withdrawn from contract");
    //     assertEq(subscription.withdrawable(tokenId), withdrawable - amount, "withdrawable amount reduced");
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription is active");
    //     assertEq(subscription.deposited(tokenId), initialDeposit - amount, "75 tokens deposited");
    // }
    //
    // function testWithdraw_operator() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     // approve operator
    //     vm.prank(alice);
    //     subscription.setApprovalForAll(bob, true);
    //
    //     uint64 passed = 5;
    //     setCurrentTime(currentTime + passed);
    //
    //     uint256 bobBalance = testToken.balanceOf(bob);
    //
    //     uint256 amount = 25;
    //
    //     vm.prank(bob);
    //     subscription.withdraw(tokenId, amount);
    //
    //     assertEq(bobBalance + amount, testToken.balanceOf(bob), "operator withdrew funds");
    // }
    //
    // function testWithdraw_approved() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     // approve operator
    //     vm.prank(alice);
    //     subscription.approve(bob, tokenId);
    //
    //     uint64 passed = 5;
    //     setCurrentTime(currentTime + passed);
    //
    //     uint256 bobBalance = testToken.balanceOf(bob);
    //
    //     uint256 amount = 25;
    //
    //     vm.prank(bob);
    //     subscription.withdraw(tokenId, amount);
    //
    //     assertEq(bobBalance + amount, testToken.balanceOf(bob), "approved account withdrew funds");
    // }
    //
    // function testWithdraw_all() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     uint64 passed = 5;
    //     setCurrentTime(currentTime + passed);
    //
    //     uint256 aliceBalance = testToken.balanceOf(alice);
    //     uint256 withdrawable = subscription.withdrawable(tokenId);
    //
    //     uint256 amount = withdrawable;
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);
    //
    //     vm.prank(alice);
    //     subscription.withdraw(tokenId, amount);
    //
    //     assertEq(
    //         testToken.balanceOf(alice),
    //         aliceBalance + initialDeposit - (passed * rate),
    //         "alice only reduced by 'used' amount"
    //     );
    //     assertEq(testToken.balanceOf(address(subscription)), passed * rate, "contract only contains 'used' amount");
    //     assertEq(subscription.withdrawable(tokenId), 0, "withdrawable amount is 0");
    //
    //     assertFalse(subscription.isActive(tokenId), "subscription is inactive");
    //     assertEq(subscription.deposited(tokenId), initialDeposit - amount, "25 tokens deposited");
    // }
    //
    // function testWithdraw_allAfterMint() public {
    //     uint256 initialDeposit = 10_000;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "10000 tokens deposited");
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription is active");
    //
    //     vm.prank(alice);
    //     vm.expectRevert("SUB: amount exceeds withdrawable");
    //     subscription.withdraw(tokenId, initialDeposit);
    //     assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    // }
    //
    // function testWithdraw_allAfterMint_lowAmount() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription is active");
    //
    //     vm.prank(alice);
    //     subscription.withdraw(tokenId, initialDeposit);
    //     assertEq(testToken.balanceOf(address(subscription)), 0, "all tokens withdrawn");
    //     assertEq(subscription.deposited(tokenId), 0, "all tokens withdrawn");
    // }
    //
    // function testWithdraw_revert_nonExisting() public {
    //     uint256 tokenId = 1000;
    //
    //     vm.prank(alice);
    //     vm.expectRevert("SUB: subscription does not exist");
    //     subscription.withdraw(tokenId, 10000);
    // }
    //
    // function testWithdraw_revert_notOwner() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     vm.prank(bob);
    //     vm.expectRevert("ERC721: caller is not token owner or approved");
    //     subscription.withdraw(tokenId, 10000);
    //     assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    // }
    //
    // function testWithdraw_revert_largerAmount() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     vm.prank(alice);
    //     vm.expectRevert("SUB: amount exceeds withdrawable");
    //     subscription.withdraw(tokenId, initialDeposit + 1);
    //     assertEq(testToken.balanceOf(address(subscription)), initialDeposit, "token balance not changed");
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "100 tokens deposited");
    // }
    //
    // function testCancel() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     uint64 passed = 5;
    //     setCurrentTime(currentTime + passed);
    //
    //     uint256 aliceBalance = testToken.balanceOf(alice);
    //
    //     uint256 amount = initialDeposit - passed * rate;
    //
    //     assertEq(subscription.withdrawable(tokenId), amount, "withdrawable amount is 75");
    //
    //     vm.expectEmit();
    //     emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);
    //
    //     vm.expectEmit();
    //     emit MetadataUpdate(tokenId);
    //
    //     vm.prank(alice);
    //     subscription.cancel(tokenId);
    //
    //     assertEq(testToken.balanceOf(alice), aliceBalance + amount, "alice only reduced by 'used' amount");
    //     assertEq(
    //         testToken.balanceOf(address(subscription)), initialDeposit - amount, "contract only contains 'used' amount"
    //     );
    //     assertEq(subscription.withdrawable(tokenId), 0, "withdrawable amount is 0");
    //
    //     assertFalse(subscription.isActive(tokenId), "subscription is inactive");
    //     assertEq(subscription.deposited(tokenId), initialDeposit - amount, "25 tokens deposited");
    // }
    //
    // function testCancel_afterMint() public {
    //     uint256 initialDeposit = 10_000;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertEq(subscription.deposited(tokenId), initialDeposit, "10000 tokens deposited");
    //
    //     assertTrue(subscription.isActive(tokenId), "subscription is active");
    //     assertEq(subscription.withdrawable(tokenId), 9900, "9900 tokens withdrawable due to lock");
    //
    //     vm.prank(alice);
    //     subscription.cancel(tokenId);
    //     assertEq(testToken.balanceOf(address(subscription)), 100, "token balance not changed");
    //     assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    // }
    //
    // function testCancel_revert_nonExisting() public {
    //     uint256 tokenId = 100;
    //
    //     vm.prank(alice);
    //     vm.expectRevert("SUB: subscription does not exist");
    //     subscription.cancel(tokenId);
    //     assertEq(testToken.balanceOf(address(subscription)), 0, "token balance not changed");
    // }
    //
    // function testSpent() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertEq(subscription.spent(tokenId), 0, "nothing spent yet");
    //
    //     setCurrentTime(currentTime + 1);
    //
    //     assertEq(subscription.spent(tokenId), rate, "1 block spent");
    //
    //     setCurrentTime(currentTime + 9);
    //
    //     assertEq(subscription.spent(tokenId), 10 * rate, "10 block spent");
    //
    //     setCurrentTime(currentTime + 1_000);
    //
    //     assertEq(subscription.spent(tokenId), initialDeposit, "initial funds spent");
    //     assertEq(subscription.spent(tokenId), subscription.deposited(tokenId), "all deposited funds spent");
    // }
    //
    // function testSpent_nonExisting() public {
    //     uint256 tokenId = 1234;
    //
    //     vm.expectRevert("SUB: subscription does not exist");
    //     subscription.spent(tokenId);
    // }
    //
    // function testUnspent() public {
    //     uint256 initialDeposit = 100;
    //     uint256 tokenId = mintToken(alice, initialDeposit);
    //
    //     assertEq(subscription.unspent(tokenId), 100, "All funds are still unspent");
    //
    //     setCurrentTime(currentTime + 1);
    //
    //     assertEq(subscription.unspent(tokenId), 100 - rate, "1 block was spent");
    //
    //     setCurrentTime(currentTime + 9);
    //
    //     assertEq(subscription.unspent(tokenId), 100 - 10 * rate, "10 blocks were spent");
    //
    //     setCurrentTime(currentTime + 1_000);
    //
    //     assertEq(subscription.unspent(tokenId), 0, "no funds are unspent");
    // }
    //
    // function testUnspent_nonExisting() public {
    //     uint256 tokenId = 1234;
    //
    //     vm.expectRevert("SUB: subscription does not exist");
    //     subscription.unspent(tokenId);
    // }
    //
    // function testClaimable() public {
    //     mintToken(alice, 1_000);
    //
    //     setCurrentTime(currentTime + (epochSize * 2));
    //
    //     // partial epoch + complete epoch
    //     assertEq(subscription.claimable(), 9 * rate + epochSize * rate, "claimable partial epoch");
    // }
    //
    // function testClaimable_instantly() public {
    //     setCurrentTime(10_000);
    //     mintToken(alice, 1_000);
    //
    //     assertEq(subscription.claimable(), 0, "0 of deposit is instantly claimable");
    // }
    //
    // function testClaimable_epoch0() public {
    //     mintToken(alice, 1_000);
    //
    //     uint256 diff = epochSize - currentTime;
    //     setCurrentTime(currentTime + (epochSize * 1));
    //
    //     // claim only epoch 0
    //     assertEq(subscription.claimable(), rate * diff, "partial funds of epoch 0 claimable");
    // }
    //
    // function testClaimable_expiring() public {
    //     uint256 tokenId = mintToken(alice, 100);
    //
    //     setCurrentTime(currentTime + (epochSize * 3));
    //
    //     assertFalse(subscription.isActive(tokenId), "Subscription inactive");
    //     assertEq(subscription.claimable(), 100, "all funds claimable");
    // }
    //
    // function testClaimable_tips() public {
    //     uint256 initAmount = 1_000;
    //     uint256 tokenId = mintToken(alice, initAmount);
    //     uint256 tipAmount = 100_000;
    //
    //     subscription.tip(tokenId, tipAmount, "");
    //
    //     assertEq(subscription.claimableTips(), tipAmount, "tipped funds claimable");
    //
    //     setCurrentTime(currentTime + (epochSize * 300));
    //
    //     assertEq(subscription.claimable() + subscription.claimableTips(), tipAmount + initAmount, "all funds claimable");
    // }
    //
    // function testClaim() public {
    //     uint256 tokenId = mintToken(alice, 1_000);
    //
    //     assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
    //     setCurrentTime(currentTime + (epochSize * 2));
    //
    //     // partial epoch + complete epoch
    //     uint256 claimable = subscription.claimable();
    //     assertEq(claimable, 9 * rate + epochSize * rate, "claimable partial epoch");
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit FundsClaimed(claimable, claimable);
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //
    //     assertEq(testToken.balanceOf(owner), claimable, "claimable funds transferred to owner");
    //     assertEq(subscription.activeSubShares(), 1 * Lib.MULTIPLIER_BASE, "subscriptions updated");
    //
    //     assertEq(subscription.claimable(), 0, "no funds claimable right after claim");
    //
    //     assertEq(subscription.deposited(tokenId), 1_000, "1000 tokens deposited");
    // }
    //
    // function testClaim_otherAccount() public {
    //     mintToken(alice, 1_000);
    //
    //     assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
    //     setCurrentTime(currentTime + (epochSize * 2));
    //
    //     // partial epoch + complete epoch
    //     uint256 claimable = subscription.claimable();
    //     assertEq(claimable, 9 * rate + epochSize * rate, "claimable partial epoch");
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit FundsClaimed(claimable, claimable);
    //
    //     vm.prank(owner);
    //     subscription.claim(charlie);
    //
    //     assertEq(testToken.balanceOf(charlie), claimable, "claimable funds transferred to charlie");
    // }
    //
    // function testClaim_instantly() public {
    //     setCurrentTime(10_000);
    //
    //     uint256 tokenId = mintToken(alice, 1_000);
    //
    //     // partial epoch + complete epoch
    //     uint256 claimable = subscription.claimable();
    //
    //     assertEq(claimable, 0, "no funds claimable right after claim");
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit FundsClaimed(claimable, claimable);
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //
    //     assertEq(testToken.balanceOf(owner), claimable, "claimable funds transferred to owner");
    //     assertEq(subscription.activeSubShares(), 100, "active subscriptions stay visible until epoch ends");
    //
    //     assertEq(subscription.deposited(tokenId), 1_000, "1000 tokens deposited");
    // }
    //
    // function testClaim_onlyOwner() public {
    //     vm.expectRevert();
    //     subscription.claim(owner);
    // }
    //
    // function testClaim_nextEpoch() public {
    //     uint256 tokenId = mintToken(alice, 1_000);
    //
    //     assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
    //     setCurrentTime(currentTime + (epochSize * 2));
    //
    //     // partial epoch + complete epoch
    //     uint256 claimable = subscription.claimable();
    //     uint256 totalClaimed = claimable;
    //     assertEq(claimable, 9 * rate + epochSize * rate, "claimable partial epoch");
    //     vm.expectEmit(true, true, true, true);
    //     emit FundsClaimed(claimable, totalClaimed);
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //
    //     uint256 ownerBalance = testToken.balanceOf(owner);
    //     assertEq(ownerBalance, claimable, "claimable funds transferred to owner");
    //     assertEq(subscription.activeSubShares(), 1 * Lib.MULTIPLIER_BASE, "subscriptions updated");
    //
    //     assertEq(subscription.claimable(), 0, "no funds claimable right after claim");
    //
    //     setCurrentTime(currentTime + (epochSize));
    //     claimable = subscription.claimable();
    //     totalClaimed += claimable;
    //     assertEq(claimable, epochSize * rate, "new epoch claimable");
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit FundsClaimed(claimable, totalClaimed);
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //
    //     assertEq(testToken.balanceOf(owner), ownerBalance + claimable, "new funds transferred to owner");
    //     assertEq(subscription.activeSubShares(), 1 * Lib.MULTIPLIER_BASE, "subscriptions updated");
    //
    //     assertEq(subscription.deposited(tokenId), 1_000, "1000 tokens deposited");
    // }
    //
    // function testClaim_expired() public {
    //     uint256 funds = 100;
    //     uint256 tokenId = mintToken(alice, funds);
    //
    //     assertEq(subscription.activeSubShares(), 100, "active subs become visible in current epoch");
    //     setCurrentTime(currentTime + (epochSize * 3));
    //
    //     assertFalse(subscription.isActive(tokenId), "Subscription inactive");
    //     assertEq(subscription.claimable(), funds, "all funds claimable");
    //
    //     vm.expectEmit(true, true, true, true);
    //     emit FundsClaimed(funds, funds);
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //
    //     assertEq(testToken.balanceOf(owner), funds, "all funds transferred to owner");
    //
    //     assertEq(subscription.activeSubShares(), 0, "active subs updated");
    //     assertEq(subscription.claimable(), 0, "no funds claimable right after claim");
    //
    //     assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    // }
    //
    // function testClaim_tips() public {
    //     setCurrentTime(currentTime + (epochSize * 300));
    //
    //     uint256 initAmount = 1_000;
    //     uint256 tokenId = mintToken(alice, initAmount);
    //     uint256 tipAmount = 100_000;
    //
    //     subscription.tip(tokenId, tipAmount, "");
    //
    //     assertEq(testToken.balanceOf(address(subscription)), initAmount + tipAmount, "amount in sub contract");
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //
    //     assertEq(testToken.balanceOf(owner), tipAmount, "tips claimed");
    //     assertEq(testToken.balanceOf(address(subscription)), initAmount, "sub deposit remains");
    //
    //     vm.prank(owner);
    //     subscription.claim(owner);
    //     assertEq(testToken.balanceOf(owner), tipAmount, "no additional funds added on 2nd claim");
    //     assertEq(testToken.balanceOf(address(subscription)), initAmount, "no funds transfered on 2nd claim");
    // }
    //
    // function testFuzz_SetUnsetFlags(uint256 flags) public {
    //     flags = bound(flags, 1, ALL_FLAGS);
    //     vm.prank(owner);
    //     subscription.setFlags(flags);
    //     assertTrue(subscription.flagsEnabled(flags), "flags set");
    //
    //     vm.prank(owner);
    //     subscription.setFlags(0);
    //     assertFalse(subscription.flagsEnabled(flags), "flags not set");
    // }
    //
    // function testSetFlags_invalid() public {
    //     vm.startPrank(owner);
    //     vm.expectRevert("SUB: invalid settings");
    //     subscription.setFlags(ALL_FLAGS + 1);
    // }
    //
    // function testSetFlags_notOwner() public {
    //     vm.expectRevert();
    //     subscription.setFlags(0x1);
    // }
    //
    // function testTip() public {
    //     uint256 tokenId = mintToken(alice, 100);
    //
    //     uint256 amount = 100;
    //     uint256 tokenBalance = 200;
    //     vm.startPrank(alice);
    //
    //     testToken.approve(address(subscription), amount);
    //
    //     assertEq(subscription.tips(tokenId), 0, "no tips in sub yet");
    //
    //     vm.expectEmit();
    //     emit Tipped(tokenId, amount, amount, alice, "hello world");
    //
    //     vm.expectEmit();
    //     emit MetadataUpdate(tokenId);
    //
    //     subscription.tip(tokenId, amount, "hello world");
    //
    //     assertEq(subscription.deposited(tokenId), 100, "deposit stays the same");
    //     assertEq(subscription.tips(tokenId), 100, "tips increased by sent amount");
    //     assertEq(testToken.balanceOf(address(subscription)), tokenBalance, "funds transferred");
    //     vm.stopPrank();
    //
    //     // tip from 'random' account
    //     amount = 200;
    //     tokenBalance = 400;
    //
    //     vm.expectEmit();
    //     emit Tipped(tokenId, amount, 300, address(this), "hello world");
    //
    //     subscription.tip(tokenId, amount, "hello world");
    //     assertEq(subscription.deposited(tokenId), 100, "deposit still the same");
    //     assertEq(subscription.tips(tokenId), 300, "tips increased by new sent amount");
    //     assertEq(testToken.balanceOf(address(subscription)), tokenBalance, "funds transferred 2");
    // }
    //
    // function testTip_nonExisiting() public {
    //     uint256 tokenId = 1234;
    //
    //     vm.expectRevert("SUB: subscription does not exist");
    //     subscription.tip(tokenId, 1, "bla");
    // }
    //
    // function testTip_zeroAmount() public {
    //     uint256 tokenId = mintToken(alice, 100);
    //
    //     vm.expectRevert("SUB: amount too small");
    //     subscription.tip(tokenId, 0, "bla");
    // }
    //
    // function testTip_minAmount() public {
    //     uint256 tokenId = mintToken(alice, 0);
    //
    //     subscription.tip(tokenId, 1, "min amount");
    //     assertEq(subscription.tips(tokenId), 1, "min amount of tips deposited");
    // }
    //
    // function testTip_whenPaused() public {
    //     uint256 tokenId = mintToken(alice, 100);
    //
    //     vm.prank(owner);
    //     subscription.setFlags(TIPPING_PAUSED);
    //
    //     vm.expectRevert("Flag: setting enabled");
    //     subscription.tip(tokenId, 100, "");
    // }
}

contract BurnSub is AbstractTestSub {
    constructor()
        AbstractTestSub(
            address(0),
            "name",
            "symbol",
            MetadataStruct("description", "image", "externalUrl"),
            SubSettings(new ERC20DecimalsMock(18), 0, 0, 0, 100)
        )
    {}

    function _deleteSubscription(uint256 tokenId) internal override {
        emit Burned(tokenId);
    }
}

contract MintSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _totalDeposited(uint256 tokenId) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal override {
        emit SubCreated(tokenId, amount, multiplier);
    }

    function _addToEpochs(uint256 amount, uint256 shares, uint256 rate) internal override {
        emit AddedToEpochs(amount, shares, rate);
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract RenewExtendSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _multiplier(uint256 tokenId) internal pure override returns (uint24) {
        return MULTI;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        emit SubExtended(tokenId, amount);

        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
        reactivated = false;
    }

    function _extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override
    {
        emit EpochsExtended(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function _totalDeposited(uint256 tokenId) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}

contract RenewReactivateSub is AbstractTestSub {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(address owner, SubSettings memory settings)
        AbstractTestSub(owner, "name", "symbol", MetadataStruct("description", "image", "externalUrl"), settings)
    {}

    function _multiplier(uint256 tokenId) internal pure override returns (uint24) {
        return MULTI;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        emit SubExtended(tokenId, amount);

        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
        reactivated = true;
    }

    function _addToEpochs(uint256 amount, uint256 shares, uint256 rate) internal override {
        emit EpochsAdded(amount, shares, rate);
    }

    function _totalDeposited(uint256 tokenId) internal pure override returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _asInternal(uint256 v) internal view virtual override returns (uint256) {
        return v * CONV;
    }

    function _asExternal(uint256 v) internal view virtual override returns (uint256) {
        return v / CONV;
    }
}