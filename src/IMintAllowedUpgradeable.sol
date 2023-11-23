// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMintAllowedEvents {
    event MintAllowed(address indexed sender, address indexed minter, uint256 indexed id, bool allow);

    event MintAllowedFrozen(address indexed sender, uint256 indexed id);
}

interface IMintAllowedUpgradeable is IMintAllowedEvents {
    function setMintAllowed(address minter, uint256 id, bool allow) external;

    function isMintAllowed(address minter, uint256 id) external view returns (bool);

    function getMinters(uint256 id) external view returns (address[] memory);

    function freezeMintAllowed(uint256 id) external;

    function isMintAllowedFrozen(uint256 id) external view returns (bool);
}
