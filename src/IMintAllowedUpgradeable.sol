// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Allow Minting Events
/// @notice Contains events for Allow Mint
interface IMintAllowedEvents {
    /// @notice The event is emitted when a minter's approval status is changed
    /// @param sender sender of approval status
    /// @param minter minter who's approval status is changed
    /// @param id token id
    /// @param allow status
    event MintAllowed(address indexed sender, address indexed minter, uint256 indexed id, bool allow);

    /// @notice The event is emitted a token's mint allowed status if frozen
    /// @param sender sender of approval status
    /// @param id token id
    event MintAllowedFrozen(address indexed sender, uint256 indexed id);
}

/// @title Mint Allow interface for upgradeable contracts
/// @notice Manages the mint allowance status for certain minters
/// @dev Can allow various accounts to mint tokens. Additionally, the allowance can be frozen so it can never be changed
interface IMintAllowedUpgradeable is IMintAllowedEvents {
    /// @notice set allow status for a minter on a token
    /// @param minter address
    /// @param id token type id
    /// @param allow status
    function setMintAllowed(address minter, uint256 id, bool allow) external;

    /// @notice check if minter is allowed to mint token
    /// @param minter address
    /// @param id token type id
    /// @return mint status
    function isMintAllowed(address minter, uint256 id) external view returns (bool);

    /// @notice get all minters for a specific token
    /// @param id token type id
    /// @return allowed minters
    function getMinters(uint256 id) external view returns (address[] memory);

    /// @notice freezes the minters and their approval status
    /// @param id token type id
    function freezeMintAllowed(uint256 id) external;

    /// @notice check if the approval for a specific token is frozen
    /// @param id token type id
    function isMintAllowedFrozen(uint256 id) external view returns (bool);
}