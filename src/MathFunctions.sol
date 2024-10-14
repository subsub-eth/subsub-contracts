// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library MathFunctions {
    function subTo0(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a < b) {
            return 0;
        }
        return a - b;
    }
}
