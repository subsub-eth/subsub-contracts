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

    function createToken(uint8 decimals) private returns (ERC20DecimalsMock) {
        return new ERC20DecimalsMock(decimals);
    }

    function testToInternal_18() public {
        ERC20DecimalsMock token = createToken(
            Lib.INTERNAL_DECIMALS
        );

        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(token.decimals());

        assertEq(
            externalAmount,
            internalAmount,
            "amount does not change for 18 decimals"
        );
    }

    function testToInternal_6() public {
        ERC20DecimalsMock token = createToken(6);

        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(token.decimals());

        assertEq(10_000_000_000_000_000, internalAmount, "add more decimals");
    }

    function testToInternal_24() public {
        ERC20DecimalsMock token = createToken(24);

        uint256 externalAmount = 10_000_000;
        uint256 internalAmount = externalAmount.toInternal(token.decimals());

        assertEq(10, internalAmount, "remove decimals");
    }

    function testToInternal_0() public {
        ERC20DecimalsMock token = createToken(0);

        uint256 externalAmount = 10_000;
        uint256 internalAmount = externalAmount.toInternal(token.decimals());

        assertEq(
            10_000_000_000_000_000_000_000,
            internalAmount,
            "add 18 decimals"
        );
    }

    function testToExternal_18() public {
        ERC20DecimalsMock token = createToken(
            Lib.INTERNAL_DECIMALS
        );

        uint256 internalAmount = 10_000;
        uint256 externalAmount = internalAmount.toExternal(token.decimals());

        assertEq(
            internalAmount,
            externalAmount,
            "amount does not change for 18 decimals"
        );
    }

    function testToExternal_6() public {
        ERC20DecimalsMock token = createToken(6);

        uint256 internalAmount = 10_000_000_000_000_000;
        uint256 externalAmount = internalAmount.toExternal(token.decimals());

        assertEq(10_000, externalAmount, "remove decimals");
    }

    function testToExternal_24() public {
        ERC20DecimalsMock token = createToken(24);

        uint256 internalAmount = 10;
        uint256 externalAmount = internalAmount.toExternal(token.decimals());

        assertEq(10_000_000, externalAmount, "add more decimals");
    }

    function testToExternal_0() public {
        ERC20DecimalsMock token = createToken(0);

        uint256 internalAmount = 10_000_000_000_000_000_000_000;
        uint256 externalAmount = internalAmount.toExternal(token.decimals());

        assertEq(10_000, externalAmount, "remove 18 decimals");
    }
}
