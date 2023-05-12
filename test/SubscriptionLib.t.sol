// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Subscription.sol";

import {SubscriptionLib} from "../src/SubscriptionLib.sol";

import {ERC20DecimalsMock} from "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";

contract SubscriptionLibTest is Test {
    using SubscriptionLib for uint256;

    function setUp() public {}

    function createToken(uint8 decimals) private returns (ERC20DecimalsMock) {
        return new ERC20DecimalsMock("Test", "TEST", decimals);
    }

    function testToInternal_18() public {
        ERC20DecimalsMock token = createToken(
            SubscriptionLib.INTERNAL_DECIMALS
        );

        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(token);

        assertEq(
            externalAmount,
            internalAmount,
            "amount does not change for 18 decimals"
        );
    }

    function testToInternal_6() public {
        ERC20DecimalsMock token = createToken(6);

        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(token);

        assertEq(10_000_000_000_000_000, internalAmount, "add more decimals");
    }

    function testToInternal_24() public {
        ERC20DecimalsMock token = createToken(24);

        uint256 externalAmount = 10_000_000;
        uint256 internalAmount = externalAmount.toInternal(token);

        assertEq(10, internalAmount, "remove decimals");
    }

    function testToInternal_0() public {
        ERC20DecimalsMock token = createToken(0);

        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(token);

        assertEq(
            10_000_000_000_000_000_000_000,
            internalAmount,
            "add 18 decimals"
        );
    }

    function testToExternal_18() public {
        ERC20DecimalsMock token = createToken(
            SubscriptionLib.INTERNAL_DECIMALS
        );

        uint256 internalAmount = 10_000;
        uint256 externalAmount = internalAmount.toExternal(token);

        assertEq(
            internalAmount,
            externalAmount,
            "amount does not change for 18 decimals"
        );
    }

    function testToExternal_6() public {
        ERC20DecimalsMock token = createToken(6);

        uint256 internalAmount = 10_000_000_000_000_000;
        uint256 externalAmount = internalAmount.toExternal(token);

        assertEq(10_000, externalAmount, "remove decimals");
    }

    function testToExternal_24() public {
        ERC20DecimalsMock token = createToken(24);

        uint256 internalAmount = 10;
        uint256 externalAmount = internalAmount.toExternal(token);

        assertEq(10_000_000, externalAmount, "add more decimals");
    }

    function testToExternal_0() public {
        ERC20DecimalsMock token = createToken(0);

        uint256 internalAmount = 10_000_000_000_000_000_000_000;
        uint256 externalAmount = internalAmount.toExternal(token);

        assertEq(10_000, externalAmount, "remove 18 decimals");
    }
}
