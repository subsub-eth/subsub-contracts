// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISubscription} from "./ISubscription.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract Subscription is ISubscription, ERC721 {
    // TODO add Ownable
    // should the tokenId 0 == owner?
    // TODO events
    // TODO add messages to deposits

    using SafeERC20 for IERC20;

    struct SubscriptionData {
        uint256 start; // mint date
        uint256 totalDeposit; // amount of tokens ever deposited
        uint256 lastDeposit; // data of last deposit
        uint256 currentDeposit; // amount of tokens at lastDeposit
    }

    uint256 public totalSupply;

    IERC20 public token;

    mapping(uint256 => SubscriptionData) private subscriptionData;

    /// @notice rate per block
    /// @dev the amount of tokens paid per block
    uint256 public rate;

    // TODO lock % of the deposit
    uint256 public lock;

    constructor(IERC20 _token, uint256 _rate) ERC721("Subscription", "SUB") {
        // TODO init with owner properties for proxy: name, symbol, rate
        token = _token;
        rate = _rate;
    }

    /// @notice "Mints" a new subscription token
    function mint(uint256 amount) external returns (uint256) {
        // TODO check minimum amount?
        // uint subscriptionEnd = amount / rate;
        uint256 tokenId = ++totalSupply;

        subscriptionData[tokenId].start = block.number;
        subscriptionData[tokenId].lastDeposit = block.number;
        subscriptionData[tokenId].totalDeposit = amount;
        subscriptionData[tokenId].currentDeposit = amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        return tokenId;
    }

    /// @notice adds deposits to an existing subscription token
    function deposit(uint256 tokenId, uint256 amount) external {
        require(_exists(tokenId), "SUB: subscription does not exist");

        uint256 end = _subscriptionEnd(tokenId);

        uint256 remaining = 0;
        if (end > block.number) {
            remaining = (end - block.number) * rate;
        }

        subscriptionData[tokenId].currentDeposit = remaining + amount;
        subscriptionData[tokenId].lastDeposit = block.number;
        subscriptionData[tokenId].totalDeposit += amount;
    }

    function withdraw(uint256 tokenId, uint256 amount) external {
        _withdraw(tokenId, amount);
    }

    function withdrawAll(uint256 tokenId) external {
        _withdraw(tokenId, _withdrawable(tokenId));
    }

    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(_exists(tokenId), "SUB: subscription does not exist");
        require(msg.sender == ownerOf(tokenId), "SUB: not the owner");

        uint256 withdrawable_ = _withdrawable(tokenId);
        require(amount <= withdrawable_, "SUB: amount exceeds withdrawable");

        subscriptionData[tokenId].currentDeposit -= amount;
        subscriptionData[tokenId].totalDeposit -= amount;

        token.safeTransfer(msg.sender, amount);
    }

    function isActive(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "SUB: subscription does not exist");
        return _isActive(tokenId);
    }

    function _isActive(uint256 tokenId) private view returns (bool) {
        // a subscription is active form the starting block (including)
        // to the calculated end block (excluding)
        // active = [start, + deposit / rate)
        uint256 currentDeposit_ = subscriptionData[tokenId].currentDeposit;
        uint256 lastDeposit = subscriptionData[tokenId].lastDeposit;

        uint256 end = lastDeposit + (currentDeposit_ / rate);

        return block.number < end;
    }

    function currentDeposit(uint256 tokenId) external view returns (uint256) {}

    function subscriptionEnd(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "SUB: subscription does not exist");

        return _subscriptionEnd(tokenId);
    }

    function _subscriptionEnd(uint256 tokenId) internal view returns (uint256) {
        uint256 lastDeposit = subscriptionData[tokenId].lastDeposit;
        uint256 currentDeposit_ = subscriptionData[tokenId].currentDeposit;
        return lastDeposit + (currentDeposit_ / rate);
    }

    function withdrawable(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "SUB: subscription does not exist");

        return _withdrawable(tokenId);
    }

    function _withdrawable(uint256 tokenId) private view returns (uint256) {
        // TODO handle lock

        if (!_isActive(tokenId)) {
            return 0;
        }

        uint256 lastDeposit = subscriptionData[tokenId].lastDeposit;
        uint256 currentDeposit_ = subscriptionData[tokenId].currentDeposit;
        uint256 usedBlocks = block.number - lastDeposit;

        return currentDeposit_ - (usedBlocks * rate);
    }

    /// @notice The owner claims their rewards
    function claim() external {}

    function claimable() external view returns (uint256) {}
}
