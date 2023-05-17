// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Creator.sol";

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

// TODO test mint/renew with amount==0
contract CreatorTest is Test {
    Creator public creator;
    Creator public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public admin;

    address public alice;
    address public bob;

    function setUp() public {
        alice = address(10);
        bob = address(20);

        admin = new ProxyAdmin();
        implementation = new Creator();
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            abi.encodeWithSignature("initialize()")
        );
        creator = Creator(address(proxy));
    }

    function testMetadata() public {
        assertEq(implementation.name(), "", "name is not set on implementation");
        assertEq(implementation.symbol(), "", "symbol is not set on implementation");

        assertEq(creator.name(), "Creator", "name is set");
        assertEq(creator.symbol(), "CRE", "symbol is set");
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
