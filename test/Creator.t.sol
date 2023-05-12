// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Creator.sol";

// TODO test mint/renew with amount==0
contract CreatorTest is Test {
    Creator public creator;

    address public alice;
    address public bob;

    function setUp() public {
        alice = address(10);
        bob = address(20);

        creator = new Creator();
    }

    function testMint() public {
        vm.prank(alice);
        uint256 aliceTokenId = creator.mint();

        assertEq(creator.ownerOf(aliceTokenId), alice, "alice minted a token");
        assertEq(creator.totalSupply(), 1, "1 token minted");

        vm.prank(bob);
        uint256 bobTokenId = creator.mint();
        assertEq(creator.ownerOf(bobTokenId), bob, "bob minted a token");

        assertLt(aliceTokenId, bobTokenId, "token ids are unique");

        assertEq(creator.totalSupply(), 2, "2 tokens minted");
    }
}
