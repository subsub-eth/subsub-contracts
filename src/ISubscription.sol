// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface SubscriptionEvents {
    event SubscriptionRenewed(
        uint256 indexed tokenId,
        uint256 indexed addedAmount,
        uint256 indexed deposited,
        address depositor,
        string message
    );

    event SubscriptionWithdrawn(
        uint256 indexed tokenId,
        uint256 indexed removedAmount,
        uint256 indexed deposited
    );
}

interface Subscribable is SubscriptionEvents {
    /// @notice adds deposits to an existing subscription token
    function renew(
        uint256 tokenId,
        uint256 amount,
        string calldata message
    ) external;

    function withdraw(uint256 tokenId, uint256 amount) external;

    function cancel(uint256 tokenId) external;

    function isActive(uint256 tokenId) external view returns (bool);

    function expiresAt(uint256 tokenId) external view returns (uint256);

    function deposited(uint256 tokenId) external view returns (uint256);

    function withdrawable(uint256 tokenId) external view returns (uint256);

    function activeSubscriptions() external view returns (uint256);
}

interface ClaimEvents {
    event FundsClaimed(uint256 amount, uint256 totalClaimed);
}

interface Claimable is ClaimEvents {
    /// @notice The owner claims their rewards
    function claim() external;

    function claimable() external view returns (uint256);
}

interface ISubscription is IERC721, Subscribable, Claimable {
    /// @notice "Mints" a new subscription token
    function mint(uint256 amount, string calldata message)
        external
        returns (uint256);
}
