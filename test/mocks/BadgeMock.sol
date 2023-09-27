// SPDX-License-Identifier: MIV
pragma solidity ^0.8.20;

import "../../src/badge/IBadge.sol";

import {ERC1155Mock} from "./ERC1155Mock.sol";

contract BadgeMock is IBadgeOperations, ERC1155Mock {
    function mint(address to, uint256 id, uint256 amount, bytes memory data)
        public
        override(IBadgeOperations, ERC1155Mock)
    {
        super.mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external {}

    function burn(address account, uint256 id, uint256 value) public override(IBadgeOperations, ERC1155Mock) {
        super.burn(account, id, value);
    }

    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) external {}
}
