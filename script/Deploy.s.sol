// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import {ERC6551Registry} from "erc6551/ERC6551Registry.sol";
import {IERC6551Executable} from "erc6551/interfaces/IERC6551Executable.sol";

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
import {BadgeHandle, UpgradeableBadgeHandle} from "../src/badge/handle/BadgeHandle.sol";
import {Badge} from "../src/badge/Badge.sol";

contract DeployDummy {}

contract DeployScript is Script {
    address private deployDummy;

    MetadataStruct private metadata;
    SubSettings private settings;

    string private anvilSeed = "test test test test test test test test test test test junk";

    address private deployer;
    address private alice;
    address private bob;
    address private charlie;
    address private dora;

    ERC20DecimalsMock private testUsd;

    bytes32 private salt = 0;

    Profile private profile;
    SubscriptionHandle private subHandle;
    BadgeHandle private badgeHandle;

    // ERC6551
    address constant erc6551RegistryAddress = 0x000000006551c19487814612e58FE06813775758;
    ERC6551Registry private erc6551Registry = ERC6551Registry(erc6551RegistryAddress);

    address private erc6551AccountImplementation;
    address private erc6551AccountProxy;

    function setUp() public {
        metadata = MetadataStruct(
            "You gain access to my heart", "https://picsum.photos/800/600", "https://example.com"
        );

        settings.token = IERC20Metadata(address(1));
        settings.rate = 1;
        settings.lock = 0;
        settings.epochSize = 100;
        settings.maxSupply = 10_000;
    }

    function run() public {
        {
            uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));

            if (deployerKey == 0) {
                // if no private key is set, we will get a test key
                deployerKey = vm.deriveKey(anvilSeed, 0);
            }
            deployer = vm.rememberKey(deployerKey);
        }

        {
            vm.startBroadcast(deployer);
            vm.recordLogs();

            // simple Test Deployment

            //////////////////////////////////////////////////////////////////////
            // DEPLOY DEPLOY_DUMMY for chicken & egg proxy setups
            //////////////////////////////////////////////////////////////////////

            deployDummy = address(new DeployDummy());

            //////////////////////////////////////////////////////////////////////
            // DEPLOY PROFILE
            //////////////////////////////////////////////////////////////////////

            Profile profileImplementation = new Profile();
            TransparentUpgradeableProxy profileProxy = new TransparentUpgradeableProxy(
                address(profileImplementation), deployer, abi.encodeWithSignature("initialize()")
            );

            address proxyAdminAddress;
            {
                Vm.Log[] memory logs = vm.getRecordedLogs();

                // get the ProxyAdmin address
                proxyAdminAddress = getProxyAdminAddressFromLogs(logs);
            }

            profile = Profile(address(profileProxy));

            console.log("Profile Contract Implementation", address(profileImplementation));
            console.log("Profile Proxy Admin", proxyAdminAddress);
            console.log("Profile Contract Proxy", address(profile));

            //////////////////////////////////////////////////////////////////////
            // DEPLOY SUBSCRIPTION + SUBSCRIPTION_HANDLE
            //////////////////////////////////////////////////////////////////////

            {
                // Handling chicken & egg problem: handle + subscription reference each other
                // create handle implementation with a dummy subscription beacon
                TransparentUpgradeableProxy subHandleProxy = new TransparentUpgradeableProxy(deployDummy, deployer, "");

                address subHandleAdminAddress;
                {
                    Vm.Log[] memory logs = vm.getRecordedLogs();

                    // get the ProxyAdmin address
                    subHandleAdminAddress = getProxyAdminAddressFromLogs(logs);
                }

                subHandle = SubscriptionHandle(address(subHandleProxy));

                // create Subscription Implementation with a reference to the CORRECT handle proxy
                Subscription subscriptionImplementation = new BlockSubscription(address(subHandle));
                UpgradeableBeacon subscriptionBeacon =
                    new UpgradeableBeacon(address(subscriptionImplementation), deployer);

                // fix the handle => sub reference by upgrading the handle implementation with the correct beacon ref
                UpgradeableSubscriptionHandle subHandleImpl =
                    new UpgradeableSubscriptionHandle(address(subscriptionBeacon));
                ProxyAdmin(subHandleAdminAddress).upgradeAndCall(
                    ITransparentUpgradeableProxy(address(subHandleProxy)),
                    address(subHandleImpl),
                    abi.encodeWithSignature("initialize()")
                );

                console.log("SubHandle Implementation", address(subHandleImpl));
                console.log("SubHandle Proxy Admin", subHandleAdminAddress);
                console.log("SubHandle Proxy Contract", address(subHandle));

                console.log("Subscription Implementation", address(subscriptionImplementation));
                console.log("Subscription Beacon", address(subscriptionBeacon));
            }

            //////////////////////////////////////////////////////////////////////
            // DEPLOY BADGE + BADGE HANDLE
            //////////////////////////////////////////////////////////////////////

            {
                // Handling chicken & egg problem: handle + badge reference each other
                // create handle implementation with a dummy badge beacon
                TransparentUpgradeableProxy badgeHandleProxy =
                    new TransparentUpgradeableProxy(deployDummy, deployer, "");

                address badgeHandleAdminAddress;
                {
                    Vm.Log[] memory logs = vm.getRecordedLogs();

                    // get the ProxyAdmin address
                    badgeHandleAdminAddress = getProxyAdminAddressFromLogs(logs);
                }

                badgeHandle = BadgeHandle(address(badgeHandleProxy));

                // create Badge Implementation with a reference to the CORRECT handle proxy
                Badge badgeImplementation = new Badge(address(badgeHandle));
                UpgradeableBeacon badgescriptionBeacon = new UpgradeableBeacon(address(badgeImplementation), deployer);

                // fix the handle => badge reference by upgrading the handle implementation with the correct beacon ref
                UpgradeableBadgeHandle badgeHandleImpl = new UpgradeableBadgeHandle(address(badgescriptionBeacon));
                ProxyAdmin(badgeHandleAdminAddress).upgradeAndCall(
                    ITransparentUpgradeableProxy(address(badgeHandleProxy)),
                    address(badgeHandleImpl),
                    abi.encodeWithSignature("initialize()")
                );

                console.log("BadgeHandle Implementation", address(badgeHandleImpl));
                console.log("BadgeHandle Proxy Admin", badgeHandleAdminAddress);
                console.log("BadgeHandle Proxy Contract", address(badgeHandle));

                console.log("Badge Implementation", address(badgeImplementation));
                console.log("Badge Beacon", address(badgescriptionBeacon));
            }

            // end test deployment
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////////////////////
        // DEPLOY TEST DATA
        //////////////////////////////////////////////////////////////////////

        if (vm.envOr("DEPLOY_TEST_DATA", false)) {
            alice = vm.rememberKey(vm.deriveKey(anvilSeed, 1));
            bob = vm.rememberKey(vm.deriveKey(anvilSeed, 2));
            charlie = vm.rememberKey(vm.deriveKey(anvilSeed, 3));
            dora = vm.rememberKey(vm.deriveKey(anvilSeed, 4));

            //////////////////////////////////////////////////////////////////////
            // DEPLOY ERC6551 REGISTRY
            //////////////////////////////////////////////////////////////////////
            vm.startBroadcast(deployer);

            erc6551Registry = new ERC6551Registry();

            console.log("ERC6551 Registry", address(erc6551Registry));

            vm.stopBroadcast();
            //////////////////////////////////////////////////////////////////////
            // DEPLOY ERC6551 Account
            //////////////////////////////////////////////////////////////////////
            vm.startBroadcast(deployer);

            // TODO FIXME
            erc6551AccountImplementation =
                deployCode("lib-precompiled/erc6551/0.3.1/ERC6551AccountUpgradeable.sol/ERC6551AccountUpgradeable.json");
            console.log("ERC6551 Account Implementation", erc6551AccountImplementation);
            erc6551AccountProxy = deployCode(
                "lib-precompiled/erc6551/0.3.1/ERC6551AccountProxy.sol/ERC6551AccountProxy.json",
                abi.encode(erc6551AccountImplementation)
            );
            console.log("ERC6551 Account Proxy", erc6551AccountProxy);

            vm.stopBroadcast();
            //////////////////////////////////////////////////////////////////////
            // DEPLOY TEST ERC20 TOKEN
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(deployer);

            testUsd = new ERC20DecimalsMock(18);
            console.log("TestUSD ERC20 Token Contract", address(testUsd));
            settings.token = testUsd;

            testUsd.mint(deployer, 100_000 ether);
            testUsd.mint(alice, 100_000 ether);
            testUsd.mint(bob, 100_000 ether);
            testUsd.mint(charlie, 100_000 ether);
            testUsd.mint(dora, 100_000 ether);

            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // ALICE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(alice);
                uint256 pAlice = profile.mint(
                    "Alice",
                    "Hi, I am Alice, a super cool influencer",
                    "https://picsum.photos/id/64/600.jpg",
                    "https://example.com"
                );

                address pAliceAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pAlice);

                address aliceSubscription1 =
                    createSubscriptionPlanWithErc6551(pAliceAccount, "Tier 1 Sub", "SUBt1", metadata, settings);

                Subscription sub2 = Subscription(
                    createSubscriptionPlanWithErc6551(pAliceAccount, "Tier 2 Sub", "SUBt2", metadata, settings)
                );
                sub2.setFlags(3);

                require(
                    subHandle.ownerOf(uint256(uint160(aliceSubscription1))) == pAliceAccount,
                    "ERC6551 account not the owner"
                );
                vm.stopBroadcast();
                address[3] memory subs = [alice, bob, charlie];
                subscribeTo(subs, aliceSubscription1, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // BOB's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(bob);
                uint256 pBob = profile.mint(
                    "Bob",
                    "Hi, I am Bob, a super cool influencer",
                    "https://picsum.photos/id/91/600.jpg",
                    "https://example.com"
                );

                address pBobAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pBob);

                address plan = createSubscriptionPlanWithErc6551(pBobAccount, "Tier 1 Sub", "SUBt1", metadata, settings);
                vm.stopBroadcast();
                address[3] memory subs = [alice, charlie, dora];
                subscribeTo(subs, plan, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // CHARLIE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(charlie);
                uint256 pCharlie = profile.mint(
                    "Charlie",
                    "Hi, I am Charlie, a super cool influencer",
                    "https://picsum.photos/id/399/600.jpg",
                    "https://example.com"
                );

                address pCharlieAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pCharlie);

                address plan =
                    createSubscriptionPlanWithErc6551(pCharlieAccount, "Tier 1 Sub", "SUBt1", metadata, settings);
                vm.stopBroadcast();
                address[3] memory subs = [alice, bob, dora];
                subscribeTo(subs, plan, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // DORA's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(dora);

                address plan = subHandle.mint("Dora's Tier 1 Sub", "SUBt1", metadata, settings);

                vm.stopBroadcast();

                address[3] memory subs = [alice, bob, charlie];
                subscribeTo(subs, plan, 10 ether);
            }
        }
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

    function createSubscriptionPlanWithErc6551(
        address acc,
        string memory _name,
        string memory _symbol,
        MetadataStruct memory _metadata,
        SubSettings memory _settings
    ) private returns (address) {
        IERC6551Executable executableAccount = IERC6551Executable(acc);

        bytes memory result = executableAccount.execute(
            address(subHandle),
            0,
            abi.encodeWithSelector(SubscriptionHandle.mint.selector, _name, _symbol, _metadata, _settings),
            0
        );
        return abi.decode(result, (address));
    }

    function subscribeTo(address[3] memory subscribers, address subPlan, uint256 amount) private {
        for (uint256 i = 0; i < subscribers.length && subscribers[i] != address(0); i++) {
            address subscriber = subscribers[i];
            ISubscription plan = ISubscription(subPlan);
            vm.startBroadcast(subscriber);

            testUsd.approve(subPlan, amount);
            plan.mint(amount, 100, "Hello World!");

            vm.stopBroadcast();
        }
    }
}
