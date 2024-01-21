// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";

/**
 * @title Dummy Price Feed
 * @notice Dummy implementation for frontend testing
 */
contract DummyPriceFeed is AggregatorV3Interface {
    int256 private answer;
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setAnswer(int256 answer_) external {
        answer = answer_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 10;
        answeredInRound = 10;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        _answer = answer;
    }

    // not implemented stuff

    function description() external view returns (string memory) {}

    function version() external view returns (uint256) {}

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {}
}
