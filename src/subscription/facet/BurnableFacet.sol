// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OzContext, OzContextBind} from "../../dependency/OzContext.sol";
import {OzERC721Enumerable, OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzInitializableBind} from "../../dependency/OzInitializable.sol";

import {Burnable} from "../ISubscription.sol";

import {PaymentToken} from "../PaymentToken.sol";
import {Rate} from "../Rate.sol";
import {HasUserData, UserData} from "../UserData.sol";
import {TimestampTimeAware} from "../TimeAware.sol";

abstract contract AbstractBurnableFacet is OzContext, OzERC721Enumerable, HasUserData, Burnable {
    function burn(uint256 tokenId) external {
        // only owner of tokenId can burn
        require(__msgSender() == __ownerOf(tokenId), "SUB: not the owner");

        _deleteSubscription(tokenId);

        __burn(tokenId);
    }
}

// solhint-disable-next-line no-empty-blocks
contract BurnableFacet is
    TimestampTimeAware,
    Rate,
    PaymentToken,
    UserData,
    OzInitializableBind,
    OzContextBind,
    OzERC721EnumerableBind,
    AbstractBurnableFacet
{}
