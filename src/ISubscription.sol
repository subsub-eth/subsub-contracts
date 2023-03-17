// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface ISubscription is IERC721 {
    /// @notice "Mints" a new subscription token
    function mint(uint256 amount) external returns (uint256);

    /// @notice adds deposits to an existing subscription token
    function deposit(uint256 tokenId, uint256 amount) external;

    function withdraw(uint256 tokenId, uint256 amount) external;

    function withdrawAll(uint256 tokenId) external;

    function isActive(uint256 tokenId) external view returns (bool);

    function currentDeposit(uint256 tokenId) external view returns (uint256);

    function subscriptionEnd(uint256 tokenId) external view returns (uint256);

    function withdrawable(uint256 tokenId) external view returns (uint256);

    /// @notice The owner claims their rewards
    function claim() external;

    function claimable() external view returns (uint256);
}
