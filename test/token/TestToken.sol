// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20PresetFixedSupply} from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract TestToken is ERC20PresetFixedSupply {
    constructor(uint256 initialSupply, address owner)
        ERC20PresetFixedSupply("Test Token", "TT", initialSupply, owner)
    {}
}
