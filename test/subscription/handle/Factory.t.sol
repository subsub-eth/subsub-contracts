// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/subscription/handle/Factory.sol";
import "../../../src/subscription/Subscription.sol";
import "../../../src/subscription/ISubscription.sol";

import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {UpgradeableBeacon} from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestFactory is Factory {
    constructor(address beacon) Factory(beacon) initializer {
        __Factory_init();
    }

    function deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) public returns (address) {
        return super._deploySubscription(_name, _symbol, _metadata, _settings);
    }
}

contract TestSubscriptionInitialize is SubscriptionInitialize {
    using Strings for string;

    function initialize(string calldata tokenName, string calldata, MetadataStruct calldata, SubSettings calldata)
        external
        pure
    {
        require(!tokenName.equal("fail"), "failing");
    }

    function hello() public pure returns (string memory) {
        return "world";
    }
}

contract FactoryTest is Test {
    TestFactory private factory;

    IBeacon private beacon;
    TestSubscriptionInitialize private subscription;

    MetadataStruct private metadata;
    SubSettings private settings;

    function setUp() public {
        subscription = new TestSubscriptionInitialize();
        beacon = new UpgradeableBeacon(address(subscription), address(this));
        factory = new TestFactory(address(beacon));

        metadata = MetadataStruct("test", "test", "test");
        settings.token = address(1234);
        settings.rate = 1;
        settings.lock = 10;
        settings.epochSize = 100;
    }

    function testCreateSubscription() public {
        address result = factory.deploySubscription("test", "test", metadata, settings);

        assertTrue(result != address(0), "new contract deployed");
        assertFalse(address(subscription) == result, "subscription at new address");
        assertEq(subscription.hello(), TestSubscriptionInitialize(result).hello(), "subscription deployed");
    }

    function testCreateSubscription_initFail() public {
        vm.expectRevert();
        factory.deploySubscription("fail", "test", metadata, settings);
    }
}
