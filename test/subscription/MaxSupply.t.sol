// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/MaxSupply.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract TestMaxSupply is Initializable, MaxSupply {
    constructor(uint256 _supply) initializer {
        __MaxSupply_init(_supply);
    }

    function _checkInitializing() internal view virtual override(Initializable, OzInitializable) {
        Initializable._checkInitializing();
    }

    function maxSupply() public view returns (uint256) {
        return _maxSupply();
    }
}

contract MaxSupplyTest is Test {
    TestMaxSupply private ms;

    function setUp() public {}

    function testSetMaxSupply(uint256 _supply) public {
        ms = new TestMaxSupply(_supply);
        assertEq(_supply, ms.maxSupply(), "supply set");
    }
}
