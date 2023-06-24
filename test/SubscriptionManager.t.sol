// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ISubscriptionManager.sol";
import "../src/SubscriptionManager.sol";
import "../src/subscription/Subscription.sol";
import "../src/subscription/ISubscription.sol";

import {ERC721Mock} from "./mocks/ERC721Mock.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SubscriptionManagerTest is Test, SubscriptionManagerEvents {
    using Address for address;

    SubscriptionManager private manager;

    ERC721Mock private creator;
    uint256 private creatorTokenId;

    IBeacon private beacon;
    Subscription private subscription;

    Metadata private metadata;
    SubSettings private settings;

    address[] private createdContracts; // side effect?

    function setUp() public {
        subscription = new Subscription();
        beacon = new UpgradeableBeacon(address(subscription));
        creator = new ERC721Mock("test", "test");
        creatorTokenId = 10;

        metadata = Metadata("test", "test", "test", "test");
        settings.token = IERC20Metadata(address(1));
        settings.rate = 1;
        settings.lock = 10;
        settings.epochSize = 100;

        creator.mint(address(this), creatorTokenId);

        SubscriptionManager impl = new SubscriptionManager();

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        manager = SubscriptionManager(address(proxy));
        manager.initialize(address(beacon), address(creator));
    }

    function testCreatorContract() public {
        assertEq(
            address(creator),
            manager.creatorContract(),
            "Creator contract set"
        );
    }

    function testCreateSubscription() public {
        vm.expectEmit(true, false, false, false);
        emit SubscriptionContractCreated(creatorTokenId, address(0));

        address token = address(12345);
        settings.token = IERC20Metadata(token);

        address result = manager.createSubscription(
            "My Subscription",
            "SUB",
            metadata,
            settings,
            creatorTokenId
        );
        assertFalse(result == address(0), "contract not created");
        assertTrue(result.isContract(), "result is actually a contract");

        (IERC20Metadata resToken, , , ) = Subscription(result).settings();
        assertEq(
            token,
            address(resToken),
            "new contract initialized, token is set"
        );

        address[] memory contracts = manager.getSubscriptionContracts(
            creatorTokenId
        );
        address[] memory res = new address[](1);
        res[0] = result;
        assertEq(contracts, res, "contracts stored");
    }

    function testCreateSubscription_notTokenOwner() public {
        vm.expectRevert("Manager: Not owner of token");
        vm.startPrank(address(1234));

        manager.createSubscription(
            "My Subscription",
            "SUB",
            metadata,
            settings,
            creatorTokenId
        );
    }

    function testCreateSubscription_multipleContracts() public {
        address token = address(1);
        settings.token = IERC20Metadata(token);

        for (uint256 i = 0; i < 100; i++) {
            address result = manager.createSubscription(
                "My Subscription",
                "SUB",
                metadata,
                settings,
                creatorTokenId
            );
            assertFalse(result == address(0), "contract not created");
            assertTrue(result.isContract(), "result is actually a contract");

            (IERC20Metadata resToken, , , ) = Subscription(result).settings();
            assertEq(
                token,
                address(resToken),
                "new contract initialized, token is set"
            );
            createdContracts.push(result);
        }

        address[] memory contracts = manager.getSubscriptionContracts(
            creatorTokenId
        );
        address[] memory _createdContracts = createdContracts;
        assertEq(contracts, _createdContracts, "contracts stored");
    }
}
