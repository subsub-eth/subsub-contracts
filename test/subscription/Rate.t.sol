// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Rate.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract TestRate is Initializable, Rate {
    constructor(uint256 _rate) initializer {
        __Rate_init(_rate);
    }

    function _checkInitializing() internal view virtual override(Initializable, OzInitializable) {
        Initializable._checkInitializing();
    }

    function rate() public view returns (uint256) {
        return _rate();
    }
}

contract RateTest is Test {
    TestRate private rr;

    function setUp() public {}

    function testSetRate(uint256 _rate) public {
        rr = new TestRate(_rate);
        assertEq(_rate, rr.rate(), "rate set");
    }
}
