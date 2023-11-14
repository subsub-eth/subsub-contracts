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

contract DeployScript is Script {
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

    // ERC6551
    address constant erc6551RegistryAddress = 0x000000006551c19487814612e58FE06813775758;
    ERC6551Registry private erc6551Registry = ERC6551Registry(erc6551RegistryAddress);

    address private erc6551AccountImplementation;
    address private erc6551AccountProxy;

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
            // DEPLOY PROFILE
            //////////////////////////////////////////////////////////////////////

            Profile profileImplementation = new Profile();
            TransparentUpgradeableProxy profileProxy = new TransparentUpgradeableProxy(
                address(profileImplementation),
                deployer,
                abi.encodeWithSignature("initialize()")
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

            address dummySubscriptionBeacon = address(new BadBeaconNotContract());

            // Handling chicken & egg problem: handle + subscription reference each other
            // create handle implementation with a dummy subscription beacon
            UpgradeableSubscriptionHandle subHandleImpl =
                new UpgradeableSubscriptionHandle(address(dummySubscriptionBeacon));
            TransparentUpgradeableProxy subHandleProxy = new TransparentUpgradeableProxy(
                address(subHandleImpl),
                deployer,
                abi.encodeWithSignature("initialize()")
            );

            address subHandleAdminAddress;
            {
                Vm.Log[] memory logs = vm.getRecordedLogs();

                // get the ProxyAdmin address
                subHandleAdminAddress = getProxyAdminAddressFromLogs(logs);
            }

            subHandle = SubscriptionHandle(address(subHandleProxy));

            // create Subscription Implementation with a reference to the CORRECT handle proxy
            Subscription subscriptionImplementation = new BlockSubscription(address(subHandle));
            UpgradeableBeacon subscriptionBeacon = new UpgradeableBeacon(
            address(subscriptionImplementation),
            deployer
        );

            // fix the handle => sub reference by upgrading the handle implementation with the corrent beacon ref
            subHandleImpl = new UpgradeableSubscriptionHandle(address(subscriptionBeacon));
            ProxyAdmin(subHandleAdminAddress).upgradeAndCall(
                ITransparentUpgradeableProxy(address(subHandleProxy)), address(subHandleImpl), ""
            );

            console.log("SubHandle Implementation", address(subHandleImpl));
            console.log("SubHandle Proxy Admin", subHandleAdminAddress);
            console.log("SubHandle Proxy Contract", address(subHandle));

            console.log("Subscription Implementation", address(subscriptionImplementation));
            console.log("Subscription Beacon", address(subscriptionBeacon));

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

            address registry = address(new ERC6551Registry());
            bytes memory code = registry.code;
            address targetAddress = address(erc6551RegistryAddress);
            vm.etch(targetAddress, code);

            console.log("nft account", erc6551Registry.account(alice, keccak256("blaa"), 1, address(profile), 2));

            vm.stopBroadcast();
            //////////////////////////////////////////////////////////////////////
            // DEPLOY ERC6551 Account
            //////////////////////////////////////////////////////////////////////

            // TODO FIXME
            erc6551AccountImplementation =
                deployCode("lib-precompiled/erc6551/0.3.1/ERC6551AccountUpgradeable.sol/ERC6551AccountUpgradeable.json");
            console.log("ERC6551 Account Implementation", erc6551AccountImplementation);
            erc6551AccountProxy = deployCode(
                "lib-precompiled/erc6551/0.3.1/ERC6551AccountProxy.sol/ERC6551AccountProxy.json",
                abi.encode(erc6551AccountImplementation)
            );
            console.log("ERC6551 Account Proxy", erc6551AccountProxy);

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

            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // ALICE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(alice);
            {
                uint256 pAlice = profile.mint(
                    "Alice",
                    "Hi, I am Alice, a super cool influencer",
                    "https://example.com/profiles/alice.png",
                    "https://example.com"
                );

                address pAliceAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pAlice);

                address aliceSubscription1 =
                    createSubscriptionPlanWithErc6551(pAliceAccount, "Tier 1 Sub", "SUBt1", metadata, settings);

                require(
                    subHandle.ownerOf(uint256(uint160(aliceSubscription1))) == pAliceAccount,
                    "ERC6551 account not the owner"
                );
            }
            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // BOB's TEST DATA
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(bob);
            {
                uint256 pBob = profile.mint(
                    "Bob",
                    "Hi, I am Bob, a super cool influencer",
                    "https://example.com/profiles/bob.png",
                    "https://example.com"
                );

                address pBobAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pBob);

                createSubscriptionPlanWithErc6551(pBobAccount, "Tier 1 Sub", "SUBt1", metadata, settings);
            }

            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // CHARLIE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(charlie);
            {
                uint256 pCharlie = profile.mint(
                    "Charlie",
                    "Hi, I am Charlie, a super cool influencer",
                    "https://example.com/profiles/charlie.png",
                    "https://example.com"
                );

                address pCharlieAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pCharlie);

                createSubscriptionPlanWithErc6551(pCharlieAccount, "Tier 1 Sub", "SUBt1", metadata, settings);
            }
            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // DORA's TEST DATA
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(dora);

            subHandle.mint("Dora's Tier 1 Sub", "SUBt1", metadata, settings);

            vm.stopBroadcast();
        }

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
}
