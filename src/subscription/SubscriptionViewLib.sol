// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Subscription} from "./Subscription.sol";

import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

library SubscriptionViewLib {
    // TODO add symbol to contractURI

    using Strings for uint256;
    using Strings for address;

    function contractData(Subscription s) public view returns (string memory) {
        string memory output;
        {
            (IERC20Metadata token, uint256 rate, uint256 lock, uint256 epochSize) = s.settings();
            output = string(
                abi.encodePacked(
                    '{"trait_type":"token","value":"',
                    address(token).toHexString(),
                    '"},{"trait_type":"rate","value":',
                    rate.toString(),
                    '},{"trait_type":"lock","value":',
                    lock.toString(),
                    '},{"trait_type":"epoch_size","value":',
                    epochSize.toString(),
                    "}"
                )
            );
        }

        {
            (address ownerContract, uint256 ownerId) = s.owner();
            output = string(
                abi.encodePacked(
                    output,
                    ',{"trait_type":"owner_contract","value":"',
                    ownerContract.toHexString(),
                    '"},{"trait_type":"owner_id","value":',
                    ownerId.toString(),
                    '},{"trait_type":"owner_address","value":"',
                    s.ownerAddress().toHexString(),
                    '"}'
                )
            );
        }
        {
            output = string(
                abi.encodePacked(
                    output,
                    ',{"trait_type":"claimable","value":"',
                    s.claimable().toString(),
                    '"},{"trait_type":"total_claimed","value":"',
                    s.totalClaimed().toString(),
                    '"},{"trait_type":"paused","value":',
                    s.paused() ? "true" : "false",
                    "}"
                )
            );
        }

        (string memory description, string memory image, string memory externalUrl) = s.metadata();
        output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        s.name(),
                        '","description":"',
                        description,
                        '","image":"',
                        image,
                        '","external_url":"',
                        externalUrl,
                        '","attributes":[',
                        output,
                        "]}"
                    )
                )
            )
        );

        output = string(abi.encodePacked("data:application/json;base64,", output));

        return output;
    }

    function tokenData(Subscription s, uint256 tokenId) public view returns (string memory) {
        string memory output = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        s.symbol(),
                        " #",
                        tokenId.toString(),
                        '","description":"',
                        "A subscription of ",
                        s.name(),
                        '","image":"',
                        "",
                        '","external_url":"',
                        '","attributes":[{"trait_type":"deposited","value":',
                        s.deposited(tokenId).toString(),
                        '},{"trait_type":"withdrawable","value":',
                        s.withdrawable(tokenId).toString(),
                        "}]}"
                    )
                )
            )
        );

        return string.concat("data:application/json;base64,", output);
    }
}
