// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Subscription} from "./Subscription.sol";

import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

library ViewLib {
    // TODO add symbol to contractURI

    using Strings for uint256;
    using Strings for address;

    function contractData(Subscription s) public view returns (string memory) {
        string memory output;
        {
            (IERC20Metadata token, uint256 rate, uint256 lock, uint256 epochSize, uint256 maxSupply) = s.settings();
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
                    '},{"trait_type":"max_supply","value":',
                    maxSupply.toString(),
                    "}"
                )
            );
        }

        {
            output = string(
                abi.encodePacked(
                    output,
                    ',{"trait_type":"owner","value":"',
                    s.owner().toHexString(),
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
                    '"},{"trait_type":"deposits_claimed","value":"',
                    s.claimedDeposits().toString(),
                    '"},{"trait_type":"tips_claimed","value":"',
                    s.claimedTips().toString(),
                    '"},{"trait_type":"flags","value":"',
                    s.getFlags().toString(),
                    '"}'
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
        // TODO mind changes to contract-wide metadata need to fire ERC4906 events
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
