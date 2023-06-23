// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ERC20DecimalsMock} from "../test/mocks/ERC20DecimalsMock.sol";

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/creator/Creator.sol";
import "../src/subscription/ISubscription.sol";
import "../src/subscription/Subscription.sol";
import "../src/SubscriptionManager.sol";

contract DeployScript is Script {
    Metadata private metadata;

    function setUp() public {
        metadata = Metadata(
            "PeterTest's Tier 1",
            "You gain access to my heart",
            "https://example.com/profiles/peter-t1.png",
            "https://example.com"
        );
    }

    function run() public {
        vm.startBroadcast();

        // simple Test Deployment

        Subscription subscriptionImplementation = new Subscription();
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            address(subscriptionImplementation)
        );

        Creator creatorImplementation = new Creator();
        ProxyAdmin creatorAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy creatorProxy = new TransparentUpgradeableProxy(
                address(creatorImplementation),
                address(creatorAdmin),
                abi.encodeWithSignature("initialize()")
            );
        Creator creator = Creator(address(creatorProxy));
        console.log("Creator Contract", address(creator));

        uint256 creatorId = creator.mint(
            "PeterTest",
            "I am a super cool influencer",
            "https://example.com/profiles/peter.png",
            "https://example.com"
        );

        SubscriptionManager managerImpl = new SubscriptionManager();
        ProxyAdmin managerAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
                address(managerImpl),
                address(managerAdmin),
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    address(beacon),
                    address(creator)
                )
            );

        SubscriptionManager manager = SubscriptionManager(
            address(managerProxy)
        );
        console.log("Manager Contract", address(manager));

        if (vm.envOr("DEPLOY_TEST_TOKEN", false)) {
            ERC20DecimalsMock token = new ERC20DecimalsMock(18);
            console.log("Test ERC20 Token Contract", address(token));
            token.mint(address(this), 100_000);
            token.mint(address(10), 100_000);

            if (vm.envOr("DEPLOY_TEST_SUBSCRIPTION", false)) {
                address subscription = manager.createSubscription(
                    "My Tier 1 Subscription",
                    "SUBt1",
                    metadata,
                    address(token),
                    1,
                    0,
                    100,
                    creatorId
                );
                console.log("Subscription Contract", subscription);
            }
        }

        vm.stopBroadcast();
    }
}
