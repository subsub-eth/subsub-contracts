// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../test/token/TestToken.sol";

import "../src/Creator.sol";
import "../src/Subscription.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // simple Test Deployment

        Creator creator = new Creator();
        uint256 creatorId = creator.mint();

        if (vm.envOr("DEPLOY_TEST_TOKEN", false)) {
            TestToken token = new TestToken(100_000, address(10));

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
