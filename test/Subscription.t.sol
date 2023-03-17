// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Subscription.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "./token/TestToken.sol";

contract SubscriptionTest is Test {
    Subscription public subscription;
    IERC20 public testToken;
    uint256 public rate;

    address public alice;
    address public bob;
    address public charlie;

    function setUp() public {
        alice = address(10);
        bob = address(20);
        charlie = address(30);
        rate = 5;
        testToken = new TestToken(1_000_000, address(this));
        subscription = new Subscription(testToken, rate);

        testToken.approve(address(subscription), type(uint256).max);

        testToken.transfer(alice, 10_000);
        testToken.transfer(bob, 20_000);
    }

    function mintToken(address user, uint256 amount)
        private
        returns (uint256 tokenId)
    {
        vm.startPrank(user);
        testToken.approve(address(subscription), amount);
        tokenId = subscription.mint(amount);
        vm.stopPrank();
    }

    function testMint() public {
        uint256 tokenId = mintToken(alice, 100);

        bool active = subscription.isActive(tokenId);
        uint256 end = subscription.subscriptionEnd(tokenId);

        assertEq(tokenId, 1, "subscription has first token id");
        assertEq(end, block.number + 20, "subscription ends at 20");
        assertTrue(active, "subscription active");
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

    function testDeposit() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.subscriptionEnd(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        // fast forward
        vm.roll(block.number + 5);

        subscription.deposit(tokenId, 200);

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.subscriptionEnd(tokenId);
        assertEq(end, initialEnd + 40, "subscription ends at 60");
    }

    function testDeposit_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.deposit(tokenId, 200);
    }

    function testDeposit_afterMint() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.subscriptionEnd(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        subscription.deposit(tokenId, 200);

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.subscriptionEnd(tokenId);
        assertEq(end, initialEnd + 40, "subscription ends at 60");
    }

    function testDeposit_inActive() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.subscriptionEnd(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        // fast forward
        uint256 ff = 50;
        vm.roll(block.number + ff);
        assertFalse(subscription.isActive(tokenId), "subscription is inactive");

        subscription.deposit(tokenId, 200);

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.subscriptionEnd(tokenId);
        assertEq(end, block.number + 40, "subscription ends at 90");
    }

    function testDeposit_notOwner() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.subscriptionEnd(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        uint256 amount = 200;
        vm.startPrank(bob);

        testToken.approve(address(subscription), amount);
        subscription.deposit(tokenId, amount);

        vm.stopPrank();

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.subscriptionEnd(tokenId);
        assertEq(
            end,
            initialEnd + (amount / rate),
            "subscription end extended"
        );
    }

    function testWithdrawable() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;

        vm.roll(block.number + passed);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit - (passed * rate),
            "withdrawable deposit 75"
        );
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
    }

    function testWithdrawable_afterMint() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit,
            "withdrawable deposit 100"
        );
    }

    function testWithdraw() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);
        uint256 subBalance = testToken.balanceOf(address(subscription));
        uint256 withdrawable = subscription.withdrawable(tokenId);

        uint256 amount = 25;

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
    }


    function testWithdraw_all() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);
        uint256 withdrawable = subscription.withdrawable(tokenId);

        uint256 amount = withdrawable;

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
    }

    function testWithdraw_allAfterMint() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 amount = initialDeposit;
        assertTrue(subscription.isActive(tokenId), "subscription is active");

        vm.prank(alice);
        subscription.withdraw(tokenId, amount);

        assertEq(
            testToken.balanceOf(alice),
            10_000,
            "alice retrieved all funds"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "contract is empty"
        );
        assertEq(subscription.withdrawable(tokenId), 0, "nothing to withdraw");

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
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
    }

    function testWithdraw_revert_largerAmount() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.prank(alice);
        vm.expectRevert("SUB: amount exceeds withdrawable");
        subscription.withdraw(tokenId, initialDeposit + 1);
    }

    function testWithdrawAll() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);

        vm.prank(alice);
        subscription.withdrawAll(tokenId);

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
    }

    function testWithdrawAll_revert_nonExisting() public {
        uint tokenId = 100;

        vm.prank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.withdrawAll(tokenId);
    }
}
