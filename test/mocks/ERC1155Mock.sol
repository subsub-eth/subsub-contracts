// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

/**
 * @title ERC1155Mock
 * This mock just provides a public safeMint, mint, and burn functions for testing purposes
 */
contract ERC1155Mock is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 amount, bytes memory data) public virtual {
        _mint(to, id, amount, data);
    }

    function burn(address from, uint256 id, uint256 amount) public virtual {
        _burn(from, id, amount);
    }
}
