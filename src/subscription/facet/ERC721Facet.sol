// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";

// solhint-disable-next-line no-empty-blocks
abstract contract AbstractERC721Facet {}

/**
 * @dev exports OZ ERC721 vanilla
 *
 */
// solhint-disable-next-line no-empty-blocks
contract ERC721Facet is OzERC721EnumerableBind, AbstractERC721Facet {}
