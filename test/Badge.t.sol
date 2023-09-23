// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/badge/Badge.sol";
import "../src/badge/IBadge.sol";

import {ERC721Mock } from "./mocks/ERC721Mock.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BadgeTest is Test {
    ERC1967Proxy public proxy;
    Badge public implementation;
    Badge public badge;

    ERC721Mock public erc721Token;

    address public owner;
    uint256 public ownerTokenId;

    function setUp() public {
        owner = address(1345275);
        ownerTokenId = 2342378482;

        erc721Token = new ERC721Mock("test", "test");

        erc721Token.mint(owner, ownerTokenId);

        implementation = new Badge();

        proxy = new ERC1967Proxy(address(implementation), "");

        badge = Badge(address(proxy));

        badge.initialize(address(erc721Token), ownerTokenId);
    }

    function testCreateToken(uint256 maxSupply) public {
        vm.assume(maxSupply > 0);
        TokenData memory td = TokenData("something", maxSupply);

        vm.startPrank(owner);
        uint256 id = badge.createToken(td);

        assertTrue(id > 0, "token id is 0");
        assertTrue(badge.exists(id), "new token does not exist");

        uint256 id2 = badge.createToken(td);

        assertTrue(id2 > 0, "token id2 is 0");
        assertNotEq(id, id2, "duplicate token id");
        assertTrue(badge.exists(id2), "new token does not exist");
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
}
