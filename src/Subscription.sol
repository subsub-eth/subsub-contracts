// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISubscription} from "./ISubscription.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "forge-std/console.sol";

contract Subscription is ISubscription, ERC721 {
    // TODO add Ownable
    // should the tokenId 0 == owner?
    // TODO events
    // TODO add messages to deposits

    using SafeERC20 for IERC20;
    using Math for uint256;

    struct SubscriptionData {
        uint256 start; // mint date
        uint256 totalDeposit; // amount of tokens ever deposited
        uint256 lastDeposit; // data of last deposit
        uint256 currentDeposit; // amount of tokens at lastDeposit
    }

    struct Epoch {
        uint256 ending; // number if ending subscriptions
        uint256 amountEnding; // amount of funds of ending subscriptions in the epoch
        uint256 starting; // number of starting subscriptions
        uint256 amountStarting; // amount of funds of starting subscriptions in the epoch
    }

    uint256 public totalSupply;

    IERC20 public token;

    mapping(uint256 => SubscriptionData) private subscriptionData;

    /// @notice rate per block
    /// @dev the amount of tokens paid per block
    uint256 public rate;

    // TODO lock % of the deposit
    uint256 public lock;

    // time of contract's inception
    // uint private creationBlock;
    uint256 private epochSize;

    uint256 private nextEpochToProcess;
    uint256 private lastProcessedEpoch;
    uint256 private activeSubs;

    mapping(uint256 => Epoch) private epochs;

    constructor(
        IERC20 _token,
        uint256 _rate,
        uint256 _epochSize
    ) ERC721("Subscription", "SUB") {
        // TODO init with owner properties for proxy: name, symbol, rate
        require(_epochSize > 0, "SUB: invalid epochSize");
        // TODO check _token not 0
        token = _token;
        // TODO check _rate > 0
        rate = _rate;
        epochSize = _epochSize;
        lastProcessedEpoch = getCurrentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    function getCurrentEpoch() internal view returns (uint256) {
        return block.number / epochSize;
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

        addNewSubscriptionToEpochs(amount);

        token.safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        return tokenId;
    }

    function addNewSubscriptionToEpochs(uint256 amount) internal {
        uint256 endingBlock = block.number + (amount / rate);

        // TODO use _subscriptionEnd(tokenId)
        // starting
        uint256 _currentEpoch = getCurrentEpoch();
        epochs[_currentEpoch].starting += 1;
        uint256 remaining = (epochSize - (block.number % epochSize)).min(
            endingBlock - block.number // subscription ends within current block
        );
        epochs[_currentEpoch].amountStarting += (remaining * rate);

        // ending
        uint256 endingEpoch = endingBlock / epochSize;
        epochs[endingEpoch].ending += 1;
        epochs[endingEpoch].amountEnding +=
            (endingBlock - (endingEpoch * epochSize)).min(
                endingBlock - block.number // subscription ends within current block
            ) *
            rate;
    }

    function moveSubscriptionInEpochs(
        uint256 _lastDeposit,
        uint256 _oldDeposit,
        uint256 _newDeposit
    ) internal {
        // when does the sub currently end?
        uint256 oldEndingBlock = _lastDeposit + (_oldDeposit / rate);
        // update old epoch
        uint256 oldEpoch = oldEndingBlock / epochSize;
        epochs[oldEpoch].ending -= 1;
        uint256 removable = (oldEndingBlock -
            ((oldEpoch * epochSize).max(block.number))) * rate;
        epochs[oldEpoch].amountEnding -= removable;

        // update new epoch
        uint256 newEndingBlock = _lastDeposit + (_newDeposit / rate);
        uint256 newEpoch = newEndingBlock / epochSize;
        epochs[newEpoch].ending += 1;
        epochs[newEpoch].amountEnding +=
            (newEndingBlock - ((newEpoch * epochSize).max(block.number))) *
            rate;
    }

    /// @notice adds deposits to an existing subscription token
    function deposit(uint256 tokenId, uint256 amount) external {
        require(_exists(tokenId), "SUB: subscription does not exist");

        uint256 oldEndingBlock = _subscriptionEnd(tokenId);

        uint256 remainingDeposit = 0;
        if (oldEndingBlock > block.number) {
            // subscription is still active
            remainingDeposit = (oldEndingBlock - block.number) * rate;

            uint256 _currentDeposit = subscriptionData[tokenId].currentDeposit;
            uint256 newDeposit = _currentDeposit + amount;
            moveSubscriptionInEpochs(
                subscriptionData[tokenId].lastDeposit,
                _currentDeposit,
                newDeposit
            );
        } else {
            // subscription is inactive
            addNewSubscriptionToEpochs(amount);
        }

        // TODO add lock
        subscriptionData[tokenId].currentDeposit = remainingDeposit + amount;
        subscriptionData[tokenId].lastDeposit = block.number;
        subscriptionData[tokenId].totalDeposit += amount;

        // finally transfer tokens into this contract
        token.safeTransferFrom(msg.sender, address(this), amount);
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

        uint256 _currentDeposit = subscriptionData[tokenId].currentDeposit;
        uint256 _lastDeposit = subscriptionData[tokenId].lastDeposit;

        uint256 newDeposit = _currentDeposit - amount;
        moveSubscriptionInEpochs(_lastDeposit, _currentDeposit, newDeposit);

        // when is is the sub going to end now?
        subscriptionData[tokenId].currentDeposit = newDeposit;
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
    function claim() external {
        require(getCurrentEpoch() > 1, "SUB: cannot handle epoch 0");
        // TODO update state;
        // TODO transfer funds;
    }

    function claimable() external view returns (uint256) {
        (uint256 amount, , ) = processEpochs();

        // TODO when optimizing, define var name in signature
        return amount;
    }

    function processEpochs()
        internal
        view
        returns (
            uint256 amount,
            uint256 starting,
            uint256 expiring
        )
    {
        uint256 _currentEpoch = getCurrentEpoch();
        uint256 _activeSubs = activeSubs;

        uint256 i;
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        if (0 == lastProcessedEpoch && _currentEpoch > 1) {
            i = 0;
        } else {
            i = lastProcessedEpoch + 1;
        }

        for (; i < _currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= epochs[i].ending;

            amount +=
                epochs[i].amountStarting +
                epochs[i].amountEnding +
                _activeSubs *
                epochSize *
                rate;
            starting += epochs[i].starting;
            expiring += epochs[i].ending;

            // add new subs starting in this epoch
            _activeSubs += epochs[i].starting;
        }
    }
}
