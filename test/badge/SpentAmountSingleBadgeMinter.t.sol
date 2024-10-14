// SPDX-License-Identifier: MIV
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/badge/IBadge.sol";
import "../../src/subscription/ISubscription.sol";

import "../../src/badge/SpentAmountSingleBadgeMinter.sol";

import {ERC721Mock} from "../mocks/ERC721Mock.sol";
import {ERC1155Mock} from "../mocks/ERC1155Mock.sol";
import {SubscriptionMock} from "../mocks/SubscriptionMock.sol";
import {BadgeMock} from "../mocks/BadgeMock.sol";

contract SpentAmountSingleBadgeMinterTest is Test {
    event SpentAmountSingleBadgeMinted(address indexed to, uint256 indexed subscriptionId, bytes data);

    BadgeMock public badge;

    SubscriptionMock public subscription;

    SpentAmountSingleBadgeMinter public minter;

    uint256 public badgeTokenId;

    uint256 public mintAmount = 1 ether;

    address public owner;
    uint256 public ownerTokenId;

    address public alice;
    address public bob;

    uint256[] private _tokenIds;
    uint256[] private _amounts;

    function setUp() public {
        owner = address(1345275);
        ownerTokenId = 2342378482;

        alice = address(298732);
        bob = address(248999423);

        badge = new BadgeMock();
        subscription = new SubscriptionMock();

        badgeTokenId = 88787878;

        minter = new SpentAmountSingleBadgeMinter(address(badge), badgeTokenId, address(subscription), mintAmount);
    }

    function testMint(uint256 amount, uint256 tokenId) public {
        vm.assume(tokenId > 0);
        amount = bound(amount, 1 ether, type(uint256).max);

        subscription.mint(alice, tokenId);
        subscription.setSpent(tokenId, amount);

        vm.prank(alice);
        vm.expectEmit();
        emit SpentAmountSingleBadgeMinted(bob, tokenId, "");

        minter.mint(bob, address(subscription), tokenId, 1, "");

        assertEq(1, badge.balanceOf(bob, badgeTokenId), "Badge not minted");
    }

    function testMint_approved(uint256 amount, uint256 tokenId) public {
        vm.assume(tokenId > 0);
        amount = bound(amount, 1 ether, type(uint256).max);

        subscription.mint(alice, tokenId);
        subscription.setSpent(tokenId, amount);

        vm.prank(alice);
        subscription.approve(bob, tokenId);

        vm.prank(bob);
        minter.mint(bob, address(subscription), tokenId, 1, "");

        assertEq(1, badge.balanceOf(bob, badgeTokenId), "Badge not minted");
    }

    function testMint_operator(uint256 amount, uint256 tokenId) public {
        vm.assume(tokenId > 0);
        amount = bound(amount, 1 ether, type(uint256).max);

        subscription.mint(alice, tokenId);
        subscription.setSpent(tokenId, amount);

        vm.prank(alice);
        subscription.setApprovalForAll(bob, true);

        vm.prank(bob);
        minter.mint(bob, address(subscription), tokenId, 1, "");

        assertEq(1, badge.balanceOf(bob, badgeTokenId), "Badge not minted");
    }

    function testMint_otherAmount(uint256 amount) public {
        vm.assume(amount != 1);

        vm.expectRevert("BadgeMint: amount != 1");
        minter.mint(bob, address(subscription), 0, amount, "");
    }

    function testMint_otherContract(address addr) public {
        vm.assume(addr != address(subscription));

        vm.expectRevert("BadgeMint: unknown Subscription Contract");
        minter.mint(bob, addr, 0, 1, "");
    }

    function testMint_notSubOwner(uint256 tokenId) public {
        vm.assume(tokenId > 0);

        subscription.mint(alice, tokenId);

        vm.prank(bob);
        vm.expectRevert("BadgeMinter: not owner of token");
        minter.mint(bob, address(subscription), tokenId, 1, "");
    }

    function testMint_amountTooLow(uint256 amount, uint256 tokenId) public {
        vm.assume(tokenId > 0);
        amount = bound(amount, 0, 1 ether - 1);

        subscription.mint(alice, tokenId);
        subscription.setSpent(tokenId, amount);

        vm.prank(alice);
        vm.expectRevert("BadgeMinter: insufficient spent amount");
        minter.mint(bob, address(subscription), tokenId, 1, "");
    }

    function testMint_twice(uint256 amount, uint256 tokenId) public {
        vm.assume(tokenId > 0);
        amount = bound(amount, 1 ether, type(uint256).max);

        subscription.mint(alice, tokenId);
        subscription.setSpent(tokenId, amount);

        vm.prank(alice);
        minter.mint(bob, address(subscription), tokenId, 1, "");

        assertEq(1, badge.balanceOf(bob, badgeTokenId), "Badge not minted");

        vm.prank(alice);
        vm.expectRevert("BadgeMinter: already minted");
        minter.mint(bob, address(subscription), tokenId, 1, "");
    }
}
