// SPDX-License-Identifier: MIT
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
    address public bob;

    ERC20DecimalsMock public testToken;

    MetadataStruct public metadata;
    SubSettings public settings;
    uint256 public rate;
    uint24 public lock;
    uint256 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    function setUp() public {
        owner = address(10);
        alice = address(11);
        bob = address(12);
        metadata = MetadataStruct("description", "image", "externalUrl");
        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;
        decimals = 12;

        testToken = new ERC20DecimalsMock(decimals);
        testToken.mint(alice, 10_000_000_000 ether);
        // bob does not receive tokens

        settings = SubSettings(address(testToken), rate, lock, epochSize, maxSupply);

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
}