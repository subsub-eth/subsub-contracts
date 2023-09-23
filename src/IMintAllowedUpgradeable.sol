// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IMintAllowedUpgradeable {

    function setMintAllowed(address minter, uint256 id, bool allow) external;

    function isMintAllowed(address minter, uint256 id) external view returns (bool);

    function freezeMintAllowed(uint256 id) external;

    function isMintAllowedFrozen(uint256 id) external view returns (bool);
}
