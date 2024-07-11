// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/subscription/Subscription.sol";

import {Lib} from "../../src/subscription/Lib.sol";

import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";

contract LibTest is Test {
    using Lib for uint256;

    function setUp() public {}

    function testToInternal_18() public pure {
        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(Lib.INTERNAL_DECIMALS);

        assertEq(externalAmount, internalAmount, "amount does not change for 18 decimals");
    }

    function testToInternal_6() public pure {
        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(6);

        assertEq(10_000_000_000_000_000, internalAmount, "add more decimals");
    }

    function testToInternal_24() public pure {
        uint256 externalAmount = 10_000_000;
        uint256 internalAmount = externalAmount.toInternal(24);

        assertEq(10, internalAmount, "remove decimals");
    }

    function testToInternal_0() public pure {
        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(0);

        assertEq(10_000_000_000_000_000_000_000, internalAmount, "add 18 decimals");
    }

    function testToExternal_18() public pure {
        uint256 internalAmount = 10_000;
        uint256 externalAmount = internalAmount.toExternal(Lib.INTERNAL_DECIMALS);

        assertEq(internalAmount, externalAmount, "amount does not change for 18 decimals");
    }

    function testToExternal_6() public pure {
        uint256 internalAmount = 10_000_000_000_000_000;
        uint256 externalAmount = internalAmount.toExternal(6);

        assertEq(10_000, externalAmount, "remove decimals");
    }

    function testToExternal_24() public pure {
        uint256 internalAmount = 10;
        uint256 externalAmount = internalAmount.toExternal(24);

        assertEq(10_000_000, externalAmount, "add more decimals");
    }

    function testToExternal_0() public pure {
        uint256 internalAmount = 10_000_000_000_000_000_000_000;
        uint256 externalAmount = internalAmount.toExternal(0);

        assertEq(10_000, externalAmount, "remove 18 decimals");
    }

    function testAsLocked() public pure {
        uint256 amount = 1_000_000;

        assertEq(0, amount.asLocked(0), "0% locked");
        assertEq(amount, amount.asLocked(Lib.LOCK_BASE), "100% locked");

        assertEq(500_000, amount.asLocked(5_000), "50% locked");
        assertEq(100_000, amount.asLocked(1_000), "10% locked");
        assertEq(10_000, amount.asLocked(100), "1% locked");
        assertEq(1_000, amount.asLocked(10), "0.1% locked");
        assertEq(100, amount.asLocked(1), "0.01% locked");

        amount = 100;
        assertEq(0, amount.asLocked(1), "floored small value");

        amount = 1_000;
        assertEq(12, amount.asLocked(123), "1.23% of too small value");
        amount = 10_000;
        assertEq(123, amount.asLocked(123), "1.23% of just large enough value");
        amount = 100_000;
        assertEq(1230, amount.asLocked(123), "1.23% of large value");
    }

    function testValidFor() public pure {
        uint256 amount = 1_000_000;
        uint256 rate = 100;

        assertEq(1, amount.validFor(amount, Lib.MULTIPLIER_BASE), "single timeunit rate");
        assertEq(0, (amount - 1).validFor(amount, Lib.MULTIPLIER_BASE), "less than 1 timeunit");
        assertEq(0, uint256(1).validFor(amount, Lib.MULTIPLIER_BASE), "1 amount");
        assertEq(0, uint256(0).validFor(amount, Lib.MULTIPLIER_BASE), "0 amount");

        assertEq(10, (amount * 10).validFor(amount, Lib.MULTIPLIER_BASE), "10 times the rate");
        assertEq(10_000, amount.validFor(rate, Lib.MULTIPLIER_BASE), "10k times the rate");
        assertEq(10_000, (amount + 10).validFor(rate, Lib.MULTIPLIER_BASE), "10k times the rate + dust");
        assertEq(10_000, (amount + 99).validFor(rate, Lib.MULTIPLIER_BASE), "10k times the rate + dust, 99");
        assertEq(10_000, (amount + 1).validFor(rate, Lib.MULTIPLIER_BASE), "10k times the rate + dust, 1");
        assertEq(10_001, (amount + rate).validFor(rate, Lib.MULTIPLIER_BASE), "10k + 1 times the rate");

        assertEq(5_000, amount.validFor(rate, 2 * Lib.MULTIPLIER_BASE), "2x multi");
        assertEq(2_500, amount.validFor(rate, 4 * Lib.MULTIPLIER_BASE), "4x multi");
        assertEq(1_250, amount.validFor(rate, 8 * Lib.MULTIPLIER_BASE), "8x multi");
        assertEq(312, amount.validFor(rate, 32 * Lib.MULTIPLIER_BASE), "32x multi");
        assertEq(156, amount.validFor(rate, 64 * Lib.MULTIPLIER_BASE), "64x multi");
        assertEq(78, amount.validFor(rate, 128 * Lib.MULTIPLIER_BASE), "128x multi");
        assertEq(39, amount.validFor(rate, 256 * Lib.MULTIPLIER_BASE), "256x multi");
        assertEq(19, amount.validFor(rate, 512 * Lib.MULTIPLIER_BASE), "512x multi");
        assertEq(9, amount.validFor(rate, 1024 * Lib.MULTIPLIER_BASE), "1024x multi");
        assertEq(4, amount.validFor(rate, 2048 * Lib.MULTIPLIER_BASE), "2048x multi");

        assertEq(8130, amount.validFor(rate, 123), "1.23x multi");
    }

    function testExpiresAt() public pure {
        uint256 amount = 1_000_000;
        uint256 rate = 100;
        uint256 t = 25;

        assertEq(10_025, amount.expiresAt(t, rate, Lib.MULTIPLIER_BASE), "10k time units");
        assertEq(5_025, amount.expiresAt(t, rate, 2 * Lib.MULTIPLIER_BASE), "2x multi");

        assertEq(26, amount.expiresAt(t, amount, Lib.MULTIPLIER_BASE), "1 time unit");
        assertEq(t, amount.expiresAt(t, amount + 1, Lib.MULTIPLIER_BASE), "rate = amount + 1, 0 time units");
        assertEq(t, (amount - 1).expiresAt(t, amount, Lib.MULTIPLIER_BASE), "amount - 1, 0 time units");
        assertEq(t, uint256(0).expiresAt(t, amount, Lib.MULTIPLIER_BASE), "0 amount, 0 time units");
    }


    function testExpiresAt_multiplied() public pure {
        uint256 amount = 1_000_000;
        uint256 rate = 100;
        uint256 t = 25;

        assertEq(10_025, amount.expiresAt(t, rate), "10k time units");

        assertEq(26, amount.expiresAt(t, amount), "1 time unit");
        assertEq(t, amount.expiresAt(t, amount + 1), "rate = amount + 1, 0 time units");
        assertEq(t, (amount - 1).expiresAt(t, amount), "amount - 1, 0 time units");
        assertEq(t, uint256(0).expiresAt(t, amount), "0 amount, 0 time units");
    }
}