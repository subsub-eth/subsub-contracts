// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBadgeMinter} from "./IBadgeMinter.sol";
import {IBadge} from "./IBadge.sol";
import {ISubscription} from "../subscription/ISubscription.sol";

import {Context} from "openzeppelin-contracts/contracts/utils/Context.sol";

// allows a one time mint per token id
// allows mint as soon as a specified amount of funds was spent in the token
contract SpentAmountSingleBadgeMinter is IBadgeMinter, Context {
    event SpentAmountSingleBadgeMinted(address indexed to, uint256 indexed subscriptionId, bytes data);

    address public immutable badgeContract;
    address public immutable subscriptionContract;
    uint256 public immutable badgeTokenId;
    uint256 public immutable spentAmount;

    mapping(uint256 => bool) private _tokenIdMinted;

    constructor(address _badgeContract, uint256 _badgeTokenId, address _subscriptionContract, uint256 _spentAmount) {
        badgeContract = _badgeContract;
        badgeTokenId = _badgeTokenId;
        subscriptionContract = _subscriptionContract;
        spentAmount = _spentAmount;
    }

    function mint(address to, address subscription, uint256 subscriptionId, uint256 amount, bytes memory data) external {
        require(amount == 1, "BadgeMint: amount != 1");
        require(subscription == subscriptionContract, "BadgeMint: unknown Subscription Contract");
        address owner = ISubscription(subscriptionContract).ownerOf(subscriptionId);
        require(
            owner == _msgSender() || ISubscription(subscriptionContract).isApprovedForAll(owner, _msgSender())
                || ISubscription(subscriptionContract).getApproved(subscriptionId) == _msgSender(),
            "BadgeMinter: not owner of token"
        );
        require(
            ISubscription(subscriptionContract).spent(subscriptionId) >= spentAmount,
            "BadgeMinter: insufficient spent amount"
        );
        require(!_tokenIdMinted[subscriptionId], "BadgeMinter: already minted");

        _tokenIdMinted[subscriptionId] = true;

        IBadge(badgeContract).mint(to, badgeTokenId, 1, data);

        emit SpentAmountSingleBadgeMinted(to, subscriptionId, data);
    }
}
