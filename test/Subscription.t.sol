// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Subscription.sol";

import {SubscriptionEvents, ClaimEvents} from "../src/ISubscription.sol";
import {Creator} from "../src/Creator.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "./token/TestToken.sol";

// TODO test mint/renew with amount==0
// TODO test lock 0% and 100%
contract SubscriptionTest is Test, SubscriptionEvents, ClaimEvents {
    Subscription public subscription;
    IERC20 public testToken;
    Creator public creator;
    uint256 public rate;
    uint256 public lock;
    uint256 public epochSize;

    address public owner;
    uint256 public ownerTokenId;
    address public alice;
    address public bob;
    address public charlie;

    string public message;

    function setUp() public {
        owner = address(1);
        alice = address(10);
        bob = address(20);
        charlie = address(30);

        message = "Hello World";

        rate = 5;
        lock = 100;
        epochSize = 10;
        creator = new Creator();
        vm.prank(owner);
        ownerTokenId = creator.mint();

        testToken = new TestToken(1_000_000, address(this));
        subscription = new Subscription(
            testToken,
            rate,
            lock,
            epochSize,
            address(creator),
            ownerTokenId
        );

        testToken.approve(address(subscription), type(uint256).max);

        testToken.transfer(alice, 100_000);
        testToken.transfer(bob, 20_000);
    }

    function testConstruct_not0token() public {
        vm.expectRevert("SUB: token cannot be 0 address");
        new Subscription(IERC20(address(0)), 10, 0, 10, address(1), 1);
    }

    function testConstruct_not0rate() public {
        vm.expectRevert("SUB: rate cannot be 0");
        new Subscription(testToken, 0, 0, 10, address(1), 1);
    }

    function testConstruct_not0epochSize() public {
        vm.expectRevert("SUB: invalid epochSize");
        new Subscription(testToken, 10, 10_000, 0, address(1), 1);
    }

    function testConstruct_lockTooLarge() public {
        vm.expectRevert("SUB: lock percentage out of range");
        new Subscription(testToken, 10, 10_001, 10, address(0), 1);
    }

    function testConstruct_not0OwnerContract() public {
        vm.expectRevert("SUB: creator address not set");
        new Subscription(testToken, 10, 0, 10, address(0), 1);
    }

    function mintToken(address user, uint256 amount)
        private
        returns (uint256 tokenId)
    {
        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(
            subscription.totalSupply() + 1,
            amount,
            (amount / rate) * rate,
            user,
            message
        );

        vm.startPrank(user);
        testToken.approve(address(subscription), amount);
        tokenId = subscription.mint(amount, message);
        vm.stopPrank();
        assertEq(
            testToken.balanceOf(address(subscription)),
            amount,
            "amount send to subscription contract"
        );

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
        assertEq(end, block.number + 20, "subscription ends at 20");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
        assertTrue(active, "subscription active");
    }

    function testMint_zeroAmount() public {
        uint256 tokenId = mintToken(alice, 0);

        bool active = subscription.isActive(tokenId);
        uint256 end = subscription.expiresAt(tokenId);

        assertEq(tokenId, 1, "subscription has first token id");
        assertEq(end, block.number, "subscription ends at current block");
        assertEq(subscription.deposited(tokenId), 0, "0 tokens deposited");
        assertFalse(active, "subscription active");
    }

    function testMint_whenPaused() public {
        vm.prank(owner);
        subscription.pause();

        vm.expectRevert("Pausable: paused");
        subscription.mint(1, "");

        vm.prank(owner);
        subscription.unpause();

        mintToken(alice, 100);
    }

    function testIsActive() public {
        uint256 tokenId = mintToken(alice, 100);

        assertEq(tokenId, 1, "subscription has first token id");

        // fast forward
        vm.roll(block.number + 5);
        bool active = subscription.isActive(tokenId);

        assertTrue(active, "subscription active");
    }

    function testIsActive_lastBlock() public {
        uint256 tokenId = mintToken(alice, 100);

        assertEq(tokenId, 1, "subscription has first token id");

        // fast forward
        vm.roll(block.number + 19);
        bool active = subscription.isActive(tokenId);

        assertTrue(active, "subscription active");

        vm.roll(block.number + 1); // + 20
        active = subscription.isActive(tokenId);

        assertFalse(active, "subscription inactive");
    }

    function testRenew() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 2000,
            "subscription initially ends at 2000"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "10_000 tokens deposited"
        );

        // fast forward
        vm.roll(block.number + 5);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(
            tokenId,
            20_000,
            30_000,
            address(this),
            message
        );

        assertFalse(subscription.paused(), "contract is not paused");

        subscription.renew(tokenId, 20_000, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            30_000,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + 4_000, "subscription expires at 6000");
        assertEq(
            subscription.deposited(tokenId),
            30_000,
            "30000 tokens deposited"
        );

        uint256 fundsUsed = 5 * rate;
        uint256 lockedAmount = ((((30_000 - fundsUsed) * lock) /
            subscription.LOCK_BASE()) / rate) * rate;
        assertEq(
            subscription.withdrawable(tokenId),
            29975 - lockedAmount,
            "Locked amount updated to 29975 - 295 = 29680"
        );
    }

    function testRenew_whenPaused() public {
        uint256 tokenId = mintToken(alice, 100);

        // fast forward
        vm.roll(block.number + 5);

        vm.prank(owner);
        subscription.pause();

        vm.expectRevert("Pausable: paused");
        subscription.renew(tokenId, 100, "");
    }

    function testRenew_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "no tokens sent"
        );
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
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + 40, "subscription ends at 60");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_inActive() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        // fast forward
        uint256 ff = 50;
        vm.roll(block.number + ff);
        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, block.number + 40, "subscription ends at 90");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_notOwner() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        uint256 amount = 200;
        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, bob, message);

        testToken.approve(address(subscription), amount);
        subscription.renew(tokenId, amount, message);

        vm.stopPrank();

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(
            end,
            initialEnd + (amount / rate),
            "subscription end extended"
        );
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testWithdrawable() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit -
                ((initialDeposit * lock) / subscription.LOCK_BASE()),
            "withdrawable deposit 9900"
        );

        uint256 passed = 50;

        vm.roll(block.number + passed);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit - (passed * rate),
            "withdrawable deposit 750"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "10000 tokens deposited"
        );
    }

    function testWithdrawable_smallDeposit() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit,
            "withdrawable deposit 100 as the deposit is too low"
        );

        uint256 passed = 5;

        vm.roll(block.number + passed);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit - (passed * rate),
            "withdrawable deposit 75"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );
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

        uint256 passed = 50;

        vm.roll(block.number + passed);

        assertFalse(subscription.isActive(tokenId), "subscription inactive");
        assertEq(
            subscription.withdrawable(tokenId),
            0,
            "withdrawable deposit 0"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
    }

    function testWithdraw() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        uint256 passed = 5;
        vm.roll(block.number + passed);

        // try withdraw 0 without effect
        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, 0, 100);

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

        assertEq(
            testToken.balanceOf(alice),
            aliceBalance + amount,
            "funds withdrawn to alice"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            subBalance - amount,
            "funds withdrawn from contract"
        );
        assertEq(
            subscription.withdrawable(tokenId),
            withdrawable - amount,
            "withdrawable amount reduced"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit - amount,
            "75 tokens deposited"
        );
    }

    function testWithdraw_all() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

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
        assertEq(
            testToken.balanceOf(address(subscription)),
            passed * rate,
            "contract only contains 'used' amount"
        );
        assertEq(
            subscription.withdrawable(tokenId),
            0,
            "withdrawable amount is 0"
        );

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit - amount,
            "25 tokens deposited"
        );
    }

    function testWithdraw_allAfterMint() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "10000 tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");

        vm.prank(alice);
        vm.expectRevert("SUB: amount exceeds withdrawable");
        subscription.withdraw(tokenId, initialDeposit);
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );
    }

    function testWithdraw_allAfterMint_lowAmount() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");

        vm.prank(alice);
        subscription.withdraw(tokenId, initialDeposit);
        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "all tokens withdrawn"
        );
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
        vm.expectRevert("SUB: not the owner");
        subscription.withdraw(tokenId, 10000);
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );
    }

    function testWithdraw_revert_largerAmount() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.prank(alice);
        vm.expectRevert("SUB: amount exceeds withdrawable");
        subscription.withdraw(tokenId, initialDeposit + 1);
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );
    }

    function testCancel() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);

        uint256 amount = initialDeposit - passed * rate;

        assertEq(
            subscription.withdrawable(tokenId),
            amount,
            "withdrawable amount is 75"
        );

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);

        vm.prank(alice);
        subscription.cancel(tokenId);

        assertEq(
            testToken.balanceOf(alice),
            aliceBalance + amount,
            "alice only reduced by 'used' amount"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit - amount,
            "contract only contains 'used' amount"
        );
        assertEq(
            subscription.withdrawable(tokenId),
            0,
            "withdrawable amount is 0"
        );

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit - amount,
            "25 tokens deposited"
        );
    }

    function testCancel_afterMint() public {
        uint256 initialDeposit = 10_000;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "10000 tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        assertEq(
            subscription.withdrawable(tokenId),
            9900,
            "9900 tokens withdrawable due to lock"
        );

        vm.prank(alice);
        subscription.cancel(tokenId);
        assertEq(
            testToken.balanceOf(address(subscription)),
            100,
            "token balance not changed"
        );
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    }

    function testCancel_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.prank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.cancel(tokenId);
        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "token balance not changed"
        );
    }

    function testSpent() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(subscription.spent(tokenId), 0, "nothing spent yet");

        vm.roll(block.number + 1);

        assertEq(subscription.spent(tokenId), rate, "1 block spent");

        vm.roll(block.number + 9);

        assertEq(subscription.spent(tokenId), 10 * rate, "10 block spent");

        vm.roll(block.number + 1_000);

        assertEq(
            subscription.spent(tokenId),
            initialDeposit,
            "initial funds spent"
        );
        assertEq(
            subscription.spent(tokenId),
            subscription.deposited(tokenId),
            "all deposited funds spent"
        );
    }

    function testSpent_nonExisting() public {
        uint256 tokenId = 1234;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.spent(tokenId);
    }

    function testClaimable() public {
        mintToken(alice, 1_000);

        vm.roll(block.number + (epochSize * 2));

        // partial epoch + complete epoch
        assertEq(
            subscription.claimable(),
            9 * rate + epochSize * rate,
            "claimable partial epoch"
        );
    }

    function testClaimable_instantly() public {
        vm.roll(10_000);
        mintToken(alice, 1_000);

        assertEq(
            subscription.claimable(),
            0,
            "0 of deposit is instantly claimable"
        );
    }

    function testClaimable_epoch0() public {
        mintToken(alice, 1_000);

        vm.roll(block.number + (epochSize * 1));

        // epoch 0 is not processed on its own
        assertEq(subscription.claimable(), 0, "no funds claimable");
    }

    function testClaimable_expiring() public {
        uint256 tokenId = mintToken(alice, 100);

        vm.roll(block.number + (epochSize * 3));

        assertFalse(subscription.isActive(tokenId), "Subscription inactive");
        assertEq(subscription.claimable(), 100, "all funds claimable");
    }

    function testClaim() public {
        uint256 tokenId = mintToken(alice, 1_000);

        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subs not updated in current epoch"
        );
        vm.roll(block.number + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        assertEq(
            claimable,
            9 * rate + epochSize * rate,
            "claimable partial epoch"
        );

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, claimable);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            1,
            "subscriptions updated"
        );

        assertEq(
            subscription.claimable(),
            0,
            "no funds claimable right after claim"
        );

        assertEq(
            subscription.deposited(tokenId),
            1_000,
            "1000 tokens deposited"
        );
    }

    function testClaim_instantly() public {
        vm.roll(10_000);

        uint256 tokenId = mintToken(alice, 1_000);

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();

        assertEq(claimable, 0, "no funds claimable right after claim");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, claimable);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subscriptions not updated"
        );

        assertEq(
            subscription.deposited(tokenId),
            1_000,
            "1000 tokens deposited"
        );
    }

    function testClaim_onlyOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        subscription.claim();
    }

    function testClaim_nextEpoch() public {
        uint256 tokenId = mintToken(alice, 1_000);

        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subs not updated in current epoch"
        );
        vm.roll(block.number + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        uint256 totalClaimed = claimable;
        assertEq(
            claimable,
            9 * rate + epochSize * rate,
            "claimable partial epoch"
        );
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, totalClaimed);

        vm.prank(owner);
        subscription.claim();

        uint256 ownerBalance = testToken.balanceOf(owner);
        assertEq(
            ownerBalance,
            claimable,
            "claimable funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            1,
            "subscriptions updated"
        );

        assertEq(
            subscription.claimable(),
            0,
            "no funds claimable right after claim"
        );

        vm.roll(block.number + (epochSize));
        claimable = subscription.claimable();
        totalClaimed += claimable;
        assertEq(claimable, epochSize * rate, "new epoch claimable");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, totalClaimed);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            ownerBalance + claimable,
            "new funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            1,
            "subscriptions updated"
        );

        assertEq(
            subscription.deposited(tokenId),
            1_000,
            "1000 tokens deposited"
        );
    }

    function testClaim_expired() public {
        uint256 funds = 100;
        uint256 tokenId = mintToken(alice, funds);

        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subs not updated in current epoch"
        );
        vm.roll(block.number + (epochSize * 3));

        assertFalse(subscription.isActive(tokenId), "Subscription inactive");
        assertEq(subscription.claimable(), funds, "all funds claimable");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(funds, funds);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            funds,
            "all funds transferred to owner"
        );

        assertEq(subscription.activeSubscriptions(), 0, "active subs updated");
        assertEq(
            subscription.claimable(),
            0,
            "no funds claimable right after claim"
        );

        assertEq(
            subscription.deposited(tokenId),
            100,
            "100 tokens deposited"
        );
    }

    function testPause() public {
        vm.prank(owner);
        subscription.pause();
        assertTrue(subscription.paused(), "contract paused");

        vm.prank(owner);
        subscription.unpause();
        assertFalse(subscription.paused(), "contract unpaused");
    }

    function testPause_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        subscription.pause();
    }

    function testUnpause_notOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        subscription.unpause();
    }

    function testTip() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 amount = 100;
        uint256 target = 200;
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Tipped(tokenId, amount, target, alice, "hello world");

        testToken.approve(address(subscription), amount);
        subscription.tip(tokenId, amount, "hello world");

        assertEq(subscription.deposited(tokenId), target, "deposit increased");
        assertEq(
            testToken.balanceOf(address(subscription)),
            target,
            "funds transferred"
        );
        vm.stopPrank();

        // tip from 'random' account
        amount = 200;
        target = 400;

        vm.expectEmit(true, true, true, true);
        emit Tipped(tokenId, amount, target, address(this), "hello world");

        subscription.tip(tokenId, amount, "hello world");
        assertEq(subscription.deposited(tokenId), target, "deposit increased");
        assertEq(
            testToken.balanceOf(address(subscription)),
            target,
            "funds transferred"
        );
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
        assertEq(subscription.deposited(tokenId), 1, "min amount deposited");
    }
}
