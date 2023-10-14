// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/profile/Profile.sol";

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

// TODO test mint/renew with amount==0
contract ProfileTest is Test {
    event Minted(address indexed to, uint256 indexed tokenId);

    Profile public profile;
    Profile public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public admin;

    address public alice;
    address public bob;

    function setUp() public {
        alice = address(10);
        bob = address(20);

        admin = new ProxyAdmin(address(this));
        implementation = new Profile();
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            abi.encodeWithSignature("initialize()")
        );
        profile = Profile(address(proxy));
    }

    function testMetadata() public {
        assertEq(implementation.name(), "", "name is not set on implementation");
        assertEq(implementation.symbol(), "", "symbol is not set on implementation");

        assertEq(profile.name(), "CreateZ Profile", "name is set");
        assertEq(profile.symbol(), "crzP", "symbol is set");
    }

    function testMint() public {
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 1);
        uint256 aliceTokenId = profile.mint("test", "test", "test", "test");

        assertEq(profile.ownerOf(aliceTokenId), alice, "alice minted a token");
        assertEq(profile.totalSupply(), 1, "1 token minted");

        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        emit Minted(bob, 2);
        uint256 bobTokenId = profile.mint("test", "test", "test", "test");
        assertEq(profile.ownerOf(bobTokenId), bob, "bob minted a token");

        assertLt(aliceTokenId, bobTokenId, "token ids are unique");

        assertEq(profile.totalSupply(), 2, "2 tokens minted");
    }
}
