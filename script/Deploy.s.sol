// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ERC20DecimalsMock} from "../test/mocks/ERC20DecimalsMock.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/profile/Profile.sol";
import "../src/subscription/ISubscription.sol";
import "../src/subscription/Subscription.sol";
import "../src/subscription/BlockSubscription.sol";
import "../src/subscription/handle/SubscriptionHandle.sol";

contract DeployScript is Script {
    MetadataStruct private metadata;
    SubSettings private settings;

    // TODO replace with json array of addresses
    address private anvilUser1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private anvilUser2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    function setUp() public {
        metadata = MetadataStruct(
            "You gain access to my heart",
            "https://example.com/profiles/peter-t1.png",
            "https://example.com"
        );

        settings.token = IERC20Metadata(address(1));
        settings.rate = 1;
        settings.lock = 0;
        settings.epochSize = 100;
        settings.maxSupply = 10_000;
    }

    function run() public {
        vm.startBroadcast();

        // simple Test Deployment

        Subscription subscriptionImplementation = new BlockSubscription();
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            address(subscriptionImplementation),
            address(this)
        );

        Profile profileImplementation = new Profile();
        ProxyAdmin profileAdmin = new ProxyAdmin(address(this));
        TransparentUpgradeableProxy profileProxy = new TransparentUpgradeableProxy(
                address(profileImplementation),
                address(profileAdmin),
                abi.encodeWithSignature("initialize()")
            );
        Profile profile = Profile(address(profileProxy));
        console.log("Profile Contract", address(profile));

        uint256 profileId = profile.mint(
            "PeterTest", "I am a super cool influencer", "https://example.com/profiles/peter.png", "https://example.com"
        );

        DefaultSubscriptionHandle handleImpl = new DefaultSubscriptionHandle();
        ProxyAdmin handleAdmin = new ProxyAdmin(address(this));
        TransparentUpgradeableProxy handleProxy = new TransparentUpgradeableProxy(
                address(handleImpl),
                address(handleAdmin),
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    address(beacon),
                    address(profile)
                )
            );

        SubscriptionHandle handle = SubscriptionHandle(address(handleProxy));
        console.log("Handle Contract", address(handle));

        if (vm.envOr("DEPLOY_TEST_TOKEN", false)) {
            ERC20DecimalsMock token = new ERC20DecimalsMock(18);
            console.log("Test ERC20 Token Contract", address(token));
            token.mint(msg.sender, 100_000 ether);
            token.mint(address(10), 100_000 ether);
            token.mint(anvilUser1, 100_000 ether);
            token.mint(anvilUser2, 100_000 ether);

            if (vm.envOr("DEPLOY_TEST_SUBSCRIPTION", false)) {
                settings.token = token;
                for (int256 i = 0; i < 6; i++) {
                    address subscription =
                        handle.mint("My Tier 1 Subscription", "SUBt1", metadata, settings);
                    console.log("Subscription Contract", subscription);

                    for (uint256 j = 0; j < 11; j++) {
                        token.approve(address(subscription), 1_000);
                        uint256 tokenId = Subscription(subscription).mint(1_000, 100, "Hello world");

                        console.log("Subscription TokenId", tokenId);
                    }
                }
            }
        }

        vm.stopBroadcast();
    }
}
