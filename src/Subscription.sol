// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISubscription} from "./ISubscription.sol";

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "forge-std/console.sol";

contract Subscription is ISubscription, ERC721, Ownable {
    // should the tokenId 0 == owner?
    // TODO pause deposits

    using SafeERC20 for IERC20;
    using Math for uint256;

    struct SubscriptionData {
        uint256 mintedAt; // mint date
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 lastDepositAt; // data of last deposit
        uint256 currentDeposit; // amount of tokens at lastDepositAt was updated
    }

    struct Epoch {
        uint256 expiring; // number of expiring subscriptions
        uint256 starting; // number of starting subscriptions
        uint256 partialFunds; // the amount of funds belonging to starting and ending subs in the epoch
    }

    uint256 public totalSupply;

    IERC20 public token;

    /// @notice rate per block
    /// @dev the amount of tokens paid per block
    uint256 public rate;

    // TODO lock % of the deposit
    uint256 public lock;

    mapping(uint256 => SubscriptionData) private subData;

    uint256 private activeSubs;

    // time of contract's inception
    // uint private creationBlock;
    uint256 private epochSize;

    uint256 private _lastProcessedEpoch;

    uint256 public totalClaimed;

    mapping(uint256 => Epoch) private epochs;

    // TODO count all claims

    constructor(
        IERC20 _token,
        uint256 _rate,
        uint256 _epochSize
    ) ERC721("Subscription", "SUB") {
        // owner is set to msg.sender
        require(_epochSize > 0, "SUB: invalid epochSize");
        require(
            address(_token) != address(0),
            "SUB: token cannot be 0 address"
        );
        require(_rate > 0, "SUB: rate cannot be 0");

        token = _token;
        rate = _rate;
        epochSize = _epochSize;

        _lastProcessedEpoch = getCurrentEpoch().max(1) - 1; // current epoch -1 or 0
    }

    function getCurrentEpoch() internal view returns (uint256) {
        return block.number / epochSize;
    }

    function activeSubscriptions() external view returns (uint256) {
        return activeSubs;
    }

    /// @notice "Mints" a new subscription token
    function mint(uint256 amount, string calldata message)
        external
        returns (uint256)
    {
        // TODO check minimum amount?
        // uint subscriptionEnd = amount / rate;
        uint256 tokenId = ++totalSupply;

        subData[tokenId].mintedAt = block.number;
        subData[tokenId].lastDepositAt = block.number;
        subData[tokenId].totalDeposited = amount;
        subData[tokenId].currentDeposit = amount;

        addNewSubscriptionToEpochs(amount);

        token.safeTransferFrom(msg.sender, address(this), amount);

        _safeMint(msg.sender, tokenId);

        emit SubscriptionRenewed(tokenId, amount, amount, msg.sender, message);

        return tokenId;
    }

    function addNewSubscriptionToEpochs(uint256 amount) internal {
        uint256 endingBlock = block.number + (amount / rate);

        // TODO use _expiresAt(tokenId)
        // starting
        uint256 _currentEpoch = getCurrentEpoch();
        epochs[_currentEpoch].starting += 1;
        uint256 remaining = (epochSize - (block.number % epochSize)).min(
            endingBlock - block.number // subscription ends within current block
        );
        epochs[_currentEpoch].partialFunds += (remaining * rate);

        // ending
        uint256 endingEpoch = endingBlock / epochSize;
        epochs[endingEpoch].expiring += 1;
        epochs[endingEpoch].partialFunds +=
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
        epochs[oldEpoch].expiring -= 1;
        uint256 removable = (oldEndingBlock -
            ((oldEpoch * epochSize).max(block.number))) * rate;
        epochs[oldEpoch].partialFunds -= removable;

        // update new epoch
        uint256 newEndingBlock = _lastDeposit + (_newDeposit / rate);
        uint256 newEpoch = newEndingBlock / epochSize;
        epochs[newEpoch].expiring += 1;
        epochs[newEpoch].partialFunds +=
            (newEndingBlock - ((newEpoch * epochSize).max(block.number))) *
            rate;
    }

    /// @notice adds deposits to an existing subscription token
    function renew(
        uint256 tokenId,
        uint256 amount,
        string calldata message
    ) external {
        require(_exists(tokenId), "SUB: subscription does not exist");

        uint256 oldEndingBlock = _expiresAt(tokenId);

        uint256 remainingDeposit = 0;
        if (oldEndingBlock > block.number) {
            // subscription is still active
            remainingDeposit = (oldEndingBlock - block.number) * rate;

            uint256 _currentDeposit = subData[tokenId].currentDeposit;
            uint256 newDeposit = _currentDeposit + amount;
            moveSubscriptionInEpochs(
                subData[tokenId].lastDepositAt,
                _currentDeposit,
                newDeposit
            );
        } else {
            // subscription is inactive
            addNewSubscriptionToEpochs(amount);
        }

        // TODO add lock
        subData[tokenId].currentDeposit = remainingDeposit + amount;
        subData[tokenId].lastDepositAt = block.number;
        subData[tokenId].totalDeposited += amount;

        // finally transfer tokens into this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit SubscriptionRenewed(
            tokenId,
            amount,
            subData[tokenId].totalDeposited, // TODO use extra var?
            msg.sender,
            message
        );
    }

    function withdraw(uint256 tokenId, uint256 amount) external {
        _withdraw(tokenId, amount);
    }

    function cancel(uint256 tokenId) external {
        _withdraw(tokenId, _withdrawable(tokenId));
    }

    function _withdraw(uint256 tokenId, uint256 amount) private {
        require(_exists(tokenId), "SUB: subscription does not exist");
        require(msg.sender == ownerOf(tokenId), "SUB: not the owner");

        uint256 withdrawable_ = _withdrawable(tokenId);
        require(amount <= withdrawable_, "SUB: amount exceeds withdrawable");

        uint256 _currentDeposit = subData[tokenId].currentDeposit;
        uint256 _lastDeposit = subData[tokenId].lastDepositAt;

        uint256 newDeposit = _currentDeposit - amount;
        moveSubscriptionInEpochs(_lastDeposit, _currentDeposit, newDeposit);

        // when is is the sub going to end now?
        subData[tokenId].currentDeposit = newDeposit;
        subData[tokenId].totalDeposited -= amount;

        token.safeTransfer(msg.sender, amount);

        emit SubscriptionWithdrawn(
            tokenId,
            amount,
            subData[tokenId].totalDeposited
        );
    }

    function isActive(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "SUB: subscription does not exist");
        return _isActive(tokenId);
    }

    function _isActive(uint256 tokenId) private view returns (bool) {
        // a subscription is active form the starting block (including)
        // to the calculated end block (excluding)
        // active = [start, + deposit / rate)
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        uint256 lastDeposit = subData[tokenId].lastDepositAt;

        uint256 end = lastDeposit + (currentDeposit_ / rate);

        return block.number < end;
    }

    function deposited(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "SUB: subscription does not exist");
        return subData[tokenId].totalDeposited;
    }

    function expiresAt(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "SUB: subscription does not exist");

        return _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view returns (uint256) {
        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
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

        uint256 lastDeposit = subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = subData[tokenId].currentDeposit;
        uint256 usedBlocks = block.number - lastDeposit;

        return currentDeposit_ - (usedBlocks * rate);
    }

    /// @notice The owner claims their rewards
    function claim() external onlyOwner {
        require(getCurrentEpoch() > 1, "SUB: cannot handle epoch 0");

        (uint256 amount, uint256 starting, uint256 expiring) = processEpochs();

        // delete epochs
        uint256 _currentEpoch = getCurrentEpoch();

        // TODO: copy claimable function body to decrease gas?
        for (uint256 i = lastProcessedEpoch(); i < _currentEpoch; i++) {
            delete epochs[i];
        }

        if (starting > expiring) {
            activeSubs += starting - expiring;
        } else {
            activeSubs -= expiring - starting;
        }

        _lastProcessedEpoch = _currentEpoch - 1;
        totalClaimed += amount;

        token.safeTransfer(owner(), amount);

        emit FundsClaimed(amount, totalClaimed);
    }

    function claimable() external view returns (uint256) {
        (uint256 amount, , ) = processEpochs();

        // TODO when optimizing, define var name in signature
        return amount;
    }

    function lastProcessedEpoch() private view returns (uint256 i) {
        // handle the lastProcessedEpoch init value of 0
        // if claimable is called before epoch 2, it will return 0
        if (0 == _lastProcessedEpoch && getCurrentEpoch() > 1) {
            i = 0;
        } else {
            i = _lastProcessedEpoch + 1;
        }
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

        for (uint256 i = lastProcessedEpoch(); i < _currentEpoch; i++) {
            // remove subs expiring in this epoch
            _activeSubs -= epochs[i].expiring;

            amount += epochs[i].partialFunds + _activeSubs * epochSize * rate;
            starting += epochs[i].starting;
            expiring += epochs[i].expiring;

            // add new subs starting in this epoch
            _activeSubs += epochs[i].starting;
        }
    }
}
