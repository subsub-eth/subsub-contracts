// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ISubscriptionManager.sol";
import "../src/SubscriptionManager.sol";
import "../src/subscription/ISubscription.sol";

import "./mocks/TestSubscription.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TestSubscriptionManager is SubscriptionManager {
    address public deployAddress;

    function setDeployAddress(address addr) public {
        deployAddress = addr;
    }

    function _deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) internal override returns (address) {
        return deployAddress;
    }
}

contract SubscriptionManagerTest is Test, SubscriptionManagerEvents {
    TestSubscriptionManager private manager;

    address private user;

    MetadataStruct private metadata;
    SubSettings private settings;

    function setUp() public {
        user = address(1000);
        metadata = MetadataStruct("test", "test", "test");
        settings.token = IERC20Metadata(address(0));
        settings.rate = 1;
        settings.lock = 10;
        settings.epochSize = 100;

        manager = new TestSubscriptionManager();
        manager.setDeployAddress(address(1234));
    }

    function testMint() public {
        vm.startPrank(user); // not a contract!
        vm.expectEmit();
        emit SubscriptionContractCreated(uint256(uint160(manager.deployAddress())), manager.deployAddress());

        address result = manager.mint("test", "test", metadata, settings);
        assertEq(result, manager.deployAddress(), "address of contract returned");

        assertEq(manager.ownerOf(uint256(uint160(result))), user, "tokenId/address minted to sender");
    }
}
