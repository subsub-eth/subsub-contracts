// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import {ERC20DecimalsMock} from "../test/mocks/ERC20DecimalsMock.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BadBeaconNotContract} from "openzeppelin-contracts/contracts/mocks/proxy/BadBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/profile/Profile.sol";
import "../src/subscription/ISubscription.sol";
import "../src/subscription/Subscription.sol";
import "../src/subscription/BlockSubscription.sol";
import "../src/subscription/handle/SubscriptionHandle.sol";

contract DeployScript is Script {
    MetadataStruct private metadata;
    SubSettings private settings;

    string private anvilSeed = "test test test test test test test test test test test junk";

    function setUp() public {
        metadata = MetadataStruct(
            "You gain access to my heart", "https://example.com/profiles/peter-t1.png", "https://example.com"
        );

        settings.token = IERC20Metadata(address(1));
        settings.rate = 1;
        settings.lock = 0;
        settings.epochSize = 100;
        settings.maxSupply = 10_000;
    }

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (deployerKey == 0) {
            // if no private key is set, we will get a test key
            deployerKey = vm.deriveKey(anvilSeed, 0);
        }
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployer);
        vm.recordLogs();
        Vm.Log[] memory logs;

        // simple Test Deployment

        //////////////////////////////////////////////////////////////////////
        // DEPLOY PROFILE
        //////////////////////////////////////////////////////////////////////

        Profile profileImplementation = new Profile();
        TransparentUpgradeableProxy profileProxy = new TransparentUpgradeableProxy(
                address(profileImplementation),
                deployer,
                abi.encodeWithSignature("initialize()")
            );

        logs = vm.getRecordedLogs();

        // get the ProxyAdmin address
        address proxyAdminAddress = getProxyAdminAddressFromLogs(logs);

        Profile profile = Profile(address(profileProxy));

        console.log("Profile Contract Implementation", address(profileImplementation));
        console.log("Profile Proxy Admin", proxyAdminAddress);
        console.log("Profile Contract Proxy", address(profile));

        //////////////////////////////////////////////////////////////////////
        // DEPLOY SUBSCRIPTION + SUBSCRIPTION_HANDLE
        //////////////////////////////////////////////////////////////////////

        address dummySubscriptionBeacon = address(new BadBeaconNotContract());

        // Handling chicken & egg problem: handle + subscription reference each other
        // create handle implementation with a dummy subscription beacon
        DefaultSubscriptionHandle subHandleImpl = new DefaultSubscriptionHandle(address(dummySubscriptionBeacon));
        TransparentUpgradeableProxy subHandleProxy = new TransparentUpgradeableProxy(
                address(subHandleImpl),
                deployer,
                abi.encodeWithSignature("initialize()")
            );
        // TODO make this kind of error shit impossible or something
        logs = vm.getRecordedLogs();
        address subHandleAdminAddress = getProxyAdminAddressFromLogs(logs);

        SubscriptionHandle subHandle = SubscriptionHandle(address(subHandleProxy));
        console.log("Handle Contract", address(subHandle));

        // create Subscription Implementation with a reference to the CORRECT handle proxy
        Subscription subscriptionImplementation = new BlockSubscription(address(subHandle));
        UpgradeableBeacon subscriptionBeacon = new UpgradeableBeacon(
            address(subscriptionImplementation),
            deployer
        );

        // fix the handle => sub reference by upgrading the handle implementation with the corrent beacon ref
        // TODO change handle implementation for immutable beacon ref
        subHandleImpl = new DefaultSubscriptionHandle(address(subscriptionBeacon));
        ProxyAdmin(subHandleAdminAddress).upgradeAndCall(
            ITransparentUpgradeableProxy(address(subHandleProxy)), address(subHandleImpl), ""
        );

        uint256 profileId = profile.mint(
            "PeterTest", "I am a super cool influencer", "https://example.com/profiles/peter.png", "https://example.com"
        );

        // if (vm.envOr("DEPLOY_TEST_TOKEN", false)) {
        //     ERC20DecimalsMock token = new ERC20DecimalsMock(18);
        //     console.log("Test ERC20 Token Contract", address(token));
        //     token.mint(msg.sender, 100_000 ether);
        //     token.mint(address(10), 100_000 ether);
        //     token.mint(anvilUser1, 100_000 ether);
        //     token.mint(anvilUser2, 100_000 ether);
        //
        //     if (vm.envOr("DEPLOY_TEST_SUBSCRIPTION", false)) {
        //         settings.token = token;
        //         for (int256 i = 0; i < 6; i++) {
        //             address subscription = handle.mint("My Tier 1 Subscription", "SUBt1", metadata, settings);
        //             console.log("Subscription Contract", subscription);
        //
        //             for (uint256 j = 0; j < 11; j++) {
        //                 token.approve(address(subscription), 1_000);
        //                 uint256 tokenId = Subscription(subscription).mint(1_000, 100, "Hello world");
        //
        //                 console.log("Subscription TokenId", tokenId);
        //             }
        //         }
        //     }
        // }

        vm.stopBroadcast();
    }

    function getProxyAdminAddressFromLogs(Vm.Log[] memory logs) private pure returns (address) {
        address addr;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("AdminChanged(address,address)")) {
                (, addr) = abi.decode(logs[i].data, (address, address));
                return addr;
            }
        }
        revert("ProxyAdmin address not found");
    }
}
