// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBadgeMinter {
    function mintableBadges() external view returns (address, uint256);

    function mint(address to, address subscription, uint256 subscriptionId, uint256 amount, bytes memory data)
        external;

    // TODO add batch minting
}
