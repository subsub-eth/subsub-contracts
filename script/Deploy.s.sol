// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ERC20DecimalsMock} from "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/Creator.sol";
import "../src/Subscription.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // simple Test Deployment

        Creator creatorImplementation = new Creator();
        ProxyAdmin creatorAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy creatorProxy =
        new TransparentUpgradeableProxy(
            address(creatorImplementation),
            address(creatorAdmin),
            abi.encodeWithSignature("initialize()")
        );
        Creator creator = Creator(address(creatorProxy));
        uint256 creatorId = creator.mint();

        if (vm.envOr("DEPLOY_TEST_TOKEN", false)) {
            ERC20DecimalsMock token = new ERC20DecimalsMock("Test", "TEST", 18);
            token.mint(address(10), 100_000);

            if (vm.envOr("DEPLOY_TEST_SUBSCRIPTION", false)) {
                Subscription subscription = new Subscription(
                    token,
                    1,
                    0,
                    100,
                    address(creator),
                    creatorId
                );
            }
        }

        vm.stopBroadcast();
    }
}
