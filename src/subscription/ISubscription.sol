// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";
import {IERC721MetadataUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";

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

    event Tipped(
        uint256 indexed tokenId,
        uint256 indexed amount,
        uint256 indexed deposited,
        address depositor,
        string message
    );
}

struct Metadata {
    string title;
    string description;
    string image;
    string externalUrl;
}

interface SubscriptionMetadata {
    function contractURI() external view returns (string memory);
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

    function spent(uint256 tokenId) external view returns (uint256);

    function withdrawable(uint256 tokenId) external view returns (uint256);

    function activeSubShares() external view returns (uint256);

    // adds funds to the subscription, but does not extend an active sub
    function tip(
        uint256 tokenId,
        uint256 amount,
        string calldata message
    ) external;
}

interface ClaimEvents {
    event FundsClaimed(uint256 amount, uint256 totalClaimed);
}

interface Claimable is ClaimEvents {
    /// @notice The owner claims their rewards
    function claim() external;

    function claimable() external view returns (uint256);

    function totalClaimed() external view returns (uint256);
}

interface ISubscription is
    IERC721Upgradeable,
    IERC721MetadataUpgradeable,
    Subscribable,
    Claimable,
    SubscriptionMetadata
{
    /// @notice "Mints" a new subscription token
    function mint(
        uint256 amount,
        uint256 multiplier,
        string calldata message
    ) external returns (uint256);
}
