// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../../src/subscription/Rate.sol";

contract TestRate is Rate {
    constructor(uint256 _rate) initializer {
        __Rate_init(_rate);
    }

    function rate() public view returns (uint256) {
        return _rate();
    }
}

contract RateTest is Test {
    using Math for uint256;

    TestRate private rr;

    function setUp() public {
    }

    function testSetRate(uint256 _rate) public {
        rr = new TestRate(_rate);
        assertEq(_rate, rr.rate(), "rate set");
    }
}