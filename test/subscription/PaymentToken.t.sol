// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import "../../src/subscription/PaymentToken.sol";

contract TestPaymentToken is PaymentToken {
    constructor(IERC20Metadata _token) initializer {
        __PaymentToken_init(_token);
    }

    function paymentToken() public view returns (IERC20Metadata) {
        return _paymentToken();
    }

    function decimals() public view returns (uint8) {
        return _decimals();
    }
}

contract PaymentTokenTest is Test {

    IERC20Metadata private token;
    TestPaymentToken private pt;

    function setUp() public {
    }

    function testSetPaymentToken(uint8 _decimals) public {
      token = new ERC20DecimalsMock(_decimals);
      pt = new TestPaymentToken(token);

      assertEq(_decimals, pt.decimals(), "decimals set");
      assertEq(address(token), address(pt.paymentToken()), "token set");
    }
}