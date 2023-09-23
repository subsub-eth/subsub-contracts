// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/badge/Badge.sol";
import "../src/badge/IBadge.sol";

import {ERC721Mock} from "./mocks/ERC721Mock.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BadgeTest is Test {
    ERC1967Proxy public proxy;
    Badge public implementation;
    Badge public badge;

    ERC721Mock public erc721Token;

    address public owner;
    uint256 public ownerTokenId;

    address public alice;
    address public bob;

    function setUp() public {
        owner = address(1345275);
        ownerTokenId = 2342378482;

        alice = address(298732);
        bob = address(248999423);

        erc721Token = new ERC721Mock("test", "test");

        erc721Token.mint(owner, ownerTokenId);

        implementation = new Badge();

        proxy = new ERC1967Proxy(address(implementation), "");

        badge = Badge(address(proxy));

        badge.initialize(address(erc721Token), ownerTokenId);
    }

    function createToken(uint256 maxSupply) private returns (uint256) {
        TokenData memory td = TokenData("some token", maxSupply);

        vm.prank(owner);
        return badge.createToken(td);
    }

    function testCreateToken(uint256 maxSupply) public {
        vm.assume(maxSupply > 0);

        uint256 id = createToken(maxSupply);

        assertTrue(id > 0, "token id is 0");
        assertTrue(badge.exists(id), "new token does not exist");
        assertEq(0, badge.totalSupply(id), "new token has supply");

        uint256 id2 = createToken(maxSupply);

        assertTrue(id2 > 0, "token id2 is 0");
        assertNotEq(id, id2, "duplicate token id");
        assertTrue(badge.exists(id2), "new token does not exist");
        assertEq(0, badge.totalSupply(id2), "new token has supply");
    }

    function testCreateToken_onlyOwner() public {
        TokenData memory td = TokenData("something", 1);

        vm.expectRevert("Ownable: caller is not the owner");
        badge.createToken(td);
    }

    function testCreateToken_noSupply() public {
        TokenData memory td = TokenData("something", 0);

        vm.expectRevert("Badge: new token maxSupply == 0");
        vm.prank(owner);
        badge.createToken(td);
    }

    function testMint(uint256 amount) public {
        // TODO allow mint amount 0?
        uint256 tokenId = createToken(type(uint256).max);

        vm.prank(owner);
        badge.setMintAllowed(alice, tokenId, true);

        vm.prank(alice);
        badge.mint(bob, tokenId, amount, "");

        assertEq(amount, badge.balanceOf(bob, tokenId), "bob did not receive tokens");
        assertEq(amount, badge.totalSupply(tokenId), "minted tokens added to supply");
    }

    function testMint_notCreated(uint256 tokenId) public {
        vm.prank(alice);
        vm.expectRevert();
        badge.mint(bob, tokenId, 1, "");
    }

    function testMint_maxSupply(uint256 amount) public {
        amount = bound(amount, 2, type(uint256).max);
        uint256 tokenId = createToken(1);

        vm.prank(owner);
        badge.setMintAllowed(alice, tokenId, true);

        vm.prank(alice);
        vm.expectRevert("Badge: exceeds max supply");
        badge.mint(bob, tokenId, amount, "");
    }

    function testMint_notAllowed() public {
        uint256 amount = 1;
        uint256 tokenId = createToken(amount);

        vm.prank(alice);
        vm.expectRevert();
        badge.mint(bob, tokenId, amount, "");
    }
}
