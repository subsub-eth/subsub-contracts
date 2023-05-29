// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ISubscriptionManager.sol";
import "../src/SubscriptionManager.sol";
import "../src/Subscription.sol";

import {ERC721Mock} from "openzeppelin-contracts/contracts/mocks/ERC721Mock.sol";

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

    address[] private createdContracts; // side effect?

    function setUp() public {
        subscription = new Subscription();
        beacon = new UpgradeableBeacon(address(subscription));
        creator = new ERC721Mock("test", "test");
        creatorTokenId = 10;

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

        address token = address(1);
        address result = manager.createSubscription(
            token,
            1,
            10,
            100,
            creatorTokenId
        );
        assertFalse(result == address(0), "contract not created");
        assertTrue(result.isContract(), "result is actually a contract");

        assertEq(
            token,
            address(Subscription(result).token()),
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

        manager.createSubscription(address(1), 1, 10, 100, creatorTokenId);
    }

    function testCreateSubscription_multipleContracts() public {
        address token = address(1);

        for (uint256 i = 0; i < 100; i++) {
            address result = manager.createSubscription(
                token,
                1,
                10,
                100,
                creatorTokenId
            );
            assertFalse(result == address(0), "contract not created");
            assertTrue(result.isContract(), "result is actually a contract");

            assertEq(
                token,
                address(Subscription(result).token()),
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
