// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/badge/Badge.sol";
import "../src/badge/IBadge.sol";

import {ERC721Mock} from "./mocks/ERC721Mock.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BadgeTest is Test, IBadgeEvents {
    ERC1967Proxy public proxy;
    Badge public implementation;
    Badge public badge;

    ERC721Mock public erc721Token;

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

        vm.expectEmit(true, false, false, false);
        emit TokenCreated(owner, 1);
        uint256 id = createToken(maxSupply);

        assertTrue(id > 0, "token id is 0");
        assertTrue(badge.exists(id), "new token does not exist");
        assertEq(0, badge.totalSupply(id), "new token has supply");

        vm.expectEmit(true, false, false, false);
        emit TokenCreated(owner, 1);
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

    function testMintBatch(uint256[] memory amounts) public {
        delete _tokenIds;
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokenId = createToken(type(uint256).max);

            vm.prank(owner);
            badge.setMintAllowed(alice, tokenId, true);

            _tokenIds.push(tokenId);
        }

        vm.prank(alice);
        badge.mintBatch(bob, _tokenIds, amounts, "");

        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(amounts[i], badge.balanceOf(bob, _tokenIds[i]), "bob did not receive tokens");
            assertEq(amounts[i], badge.totalSupply(_tokenIds[i]), "minted tokens added to supply");
        }
    }

    function testMintBatch_notCreated(uint256[] memory tokenIds) public {
        vm.assume(tokenIds.length > 0);
        delete _amounts;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _amounts.push(1);
        }

        vm.prank(alice);
        vm.expectRevert();
        badge.mintBatch(bob, _tokenIds, _amounts, "");
    }

    function testMintBatch_emptyArrays() public {
        badge.mintBatch(bob, new uint256[](0), new uint256[](0), "");
    }

    function testMintBatch_maxSupply(uint256[] memory amounts) public {
        vm.assume(amounts.length > 0);
        delete _tokenIds;

        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = bound(amounts[i], 2, type(uint256).max);

            uint256 tokenId = createToken(1);
            vm.prank(owner);
            badge.setMintAllowed(alice, tokenId, true);

            _tokenIds.push(tokenId);
        }

        vm.prank(alice);
        vm.expectRevert("Badge: exceeds max supply");
        badge.mintBatch(bob, _tokenIds, amounts, "");
    }

    function testMint_notAllowed(uint256[] memory amounts) public {
        vm.assume(amounts.length > 0);
        delete _tokenIds;
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = bound(amounts[i], 2, type(uint256).max);
            uint256 tokenId = createToken(amounts[i]);
            _tokenIds.push(tokenId);
        }

        vm.prank(alice);
        vm.expectRevert();
        badge.mintBatch(bob, _tokenIds, amounts, "");
    }

    function testBurn(uint256 amount) public {
        uint256 max = type(uint256).max;
        uint256 tokenId = createToken(max);

        vm.prank(owner);
        badge.setMintAllowed(alice, tokenId, true);

        vm.prank(alice);
        badge.mint(bob, tokenId, max, "");

        vm.prank(bob);
        badge.burn(bob, tokenId, amount);

        assertEq(max - amount, badge.balanceOf(bob, tokenId));
        assertEq(max - amount, badge.totalSupply(tokenId));
    }

    function testBurn_notOwner(uint256 amount) public {
        uint256 max = type(uint256).max;
        uint256 tokenId = createToken(max);

        vm.prank(owner);
        badge.setMintAllowed(alice, tokenId, true);

        vm.prank(alice);
        badge.mint(bob, tokenId, max, "");

        vm.expectRevert();
        badge.burn(bob, tokenId, amount);
    }

    function testBurnBatch(uint256[] memory amounts) public {
        delete _tokenIds;
        uint256 max = type(uint256).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokenId = createToken(max);
            vm.prank(owner);
            badge.setMintAllowed(alice, tokenId, true);

            vm.prank(alice);
            badge.mint(bob, tokenId, max, "");

            _tokenIds.push(tokenId);
        }

        vm.prank(bob);
        badge.burnBatch(bob, _tokenIds, amounts);

        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(max - amounts[i], badge.balanceOf(bob, _tokenIds[i]));
            assertEq(max - amounts[i], badge.totalSupply(_tokenIds[i]));
        }
    }

    function testBurnBatch_notOwner(uint256[] memory amounts) public {
        delete _tokenIds;
        uint256 max = type(uint256).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokenId = createToken(max);
            vm.prank(owner);
            badge.setMintAllowed(alice, tokenId, true);

            vm.prank(alice);
            badge.mint(bob, tokenId, max, "");

            _tokenIds.push(tokenId);
        }

        vm.expectRevert();
        badge.burnBatch(bob, _tokenIds, amounts);
    }
}
