// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20DecimalsMock as ERC20DecMock} from "openzeppelin-contracts/mocks/token/ERC20DecimalsMock.sol";

contract ERC20DecimalsMock is ERC20DecMock {
    constructor(uint8 decimals_) ERC20DecMock(decimals_) ERC20("Test Dollars", "testUSD") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
