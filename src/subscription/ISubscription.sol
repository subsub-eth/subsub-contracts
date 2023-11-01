// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from
    "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC4906} from "openzeppelin-contracts/contracts/interfaces/IERC4906.sol";

interface SubscriptionEvents {
    event SubscriptionRenewed(
        uint256 indexed tokenId,
        uint256 indexed addedAmount,
        uint256 indexed deposited,
        address depositor,
        string message
    );

    event SubscriptionWithdrawn(uint256 indexed tokenId, uint256 indexed removedAmount, uint256 indexed deposited);

    event Tipped(
        uint256 indexed tokenId, uint256 indexed amount, uint256 indexed deposited, address depositor, string message
    );
}

struct MetadataStruct {
    string description;
    string image;
    string externalUrl;
}

struct SubSettings {
    IERC20Metadata token;
    /// @notice rate per block
    /// @dev the amount of tokens paid per block based on 18 decimals
    uint256 rate;
    // locked % of deposited amount
    // 0 - 10000
    uint256 lock;
    // time of contract's inception
    uint256 epochSize;
    // max supply of subscriptions that can be minted
    uint256 maxSupply;
}

interface SubscriptionMetadata {
    function contractURI() external view returns (string memory);
}

interface Subscribable is SubscriptionEvents {
    /// @notice adds deposits to an existing subscription token
    function renew(uint256 tokenId, uint256 amount, string calldata message) external;

    function withdraw(uint256 tokenId, uint256 amount) external;

    function cancel(uint256 tokenId) external;

    function isActive(uint256 tokenId) external view returns (bool);

    function expiresAt(uint256 tokenId) external view returns (uint256);

    // the amount of tokens ever deposited reduced by the withdrawn amount.
    function deposited(uint256 tokenId) external view returns (uint256);

    // the amount of tokens spent in the subscription
    function spent(uint256 tokenId) external view returns (uint256);

    // the amount of deposited tokens that have not been spend yet
    function unspent(uint256 tokenId) external view returns (uint256);

    function withdrawable(uint256 tokenId) external view returns (uint256);

    function activeSubShares() external view returns (uint256);

    // adds funds to the subscription, but does not extend an active sub
    function tip(uint256 tokenId, uint256 amount, string calldata message) external;

    // returns the amount of tips ever sent to a subscription
    function tips(uint256 tokenId) external view returns (uint256);
}

interface ClaimEvents {
    event FundsClaimed(uint256 amount, uint256 totalClaimed);
}

interface Claimable is ClaimEvents {
    /// @notice The owner claims their rewards
    function claim(address to) external;

    function claimable() external view returns (uint256);

    function claimedDeposits() external view returns (uint256);

    function claimedTips() external view returns (uint256);
}

abstract contract SubscriptionFlags {

    uint256 public constant MINTING_PAUSED = 0x1;
    uint256 public constant RENEWAL_PAUSED = 0x2;
    uint256 public constant TIPPING_PAUSED = 0x4;

    uint256 public constant ALL_FLAGS = 0x7;
}

interface SubscriptionCreation {
    /// @notice "Mints" a new subscription token
    function mint(uint256 amount, uint24 multiplier, string calldata message) external returns (uint256);

    /// @notice "Burns" a subscription token, deletes all achieved subscription
    ///         data and does not withdraw any withdrawable funds
    function burn(uint256 tokenId) external;
}

interface SubscriptionInitialize {
    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external;
}

interface ISubscription is
    IERC721,
    IERC721Metadata,
    IERC4906,
    Subscribable,
    Claimable,
    SubscriptionCreation,
    SubscriptionMetadata,
    SubscriptionInitialize
{}
