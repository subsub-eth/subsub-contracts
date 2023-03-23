// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface SubscriptionEvents {

}

interface Subscribable is SubscriptionEvents {

    /// @notice adds deposits to an existing subscription token
    function renew(uint256 tokenId, uint256 amount) external;

    function withdraw(uint256 tokenId, uint256 amount) external;

    function cancel(uint256 tokenId) external;

    function isActive(uint256 tokenId) external view returns (bool);

    function expiresAt(uint256 tokenId) external view returns (uint256);

    function currentDeposit(uint256 tokenId) external view returns (uint256);

    function withdrawable(uint256 tokenId) external view returns (uint256);

}

interface ClaimEvents {

}

interface Claimable is ClaimEvents {

    /// @notice The owner claims their rewards
    function claim() external;

    function claimable() external view returns (uint256);
}


interface ISubscription is IERC721, Subscribable, Claimable {
    /// @notice "Mints" a new subscription token
    function mint(uint256 amount) external returns (uint256);
}
