// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "solidity-linked-list/contracts/StructuredLinkedList.sol";
import "./subscriptionlist/SubscriptionList.sol";

import "./util/Blockaware.sol";
import "./Versioned.sol";

contract CreatorVault is Ownable, Blockaware, Versioned {

  // TODO refactor _currentBlock() calls with internal method
  // TODO add name

  using SafeERC20 for IERC20;
  using SubscriptionList for SubscriptionList.List;
  using StructuredLinkedList for StructuredLinkedList.List;

  uint private _stateUpdated;
  SubscriptionList.List private subList;

  uint private _claimableEarnings = 0;

  struct UserDeposit {
    // last block of last deposit
    uint lastChangeAt;
    // total amount of tokens at last deposit
    uint amount;
    // block of first ever deposit
    uint initialDepositAt;
    // total amount of tokens ever deposited
    uint totalAmount;
  }

  event UserDeposited(
    address indexed user,
    uint amount,
    uint newDeposit,
    uint allTimeDeposit,
    uint initialDepositAt
  );

  event UserWithdrew(
    address indexed user,
    uint amount,
    uint newDeposit,
    uint allTimeDeposit,
    uint initialDepositAt
  );

  // The token this contract does accept
  IERC20 private immutable _token;

  uint private _creatorFeePerBlock;

  // initial deposits of supporters
  mapping(address => UserDeposit) private deposits;

  constructor(address _creator, address __token) {

    _token = IERC20(__token);
    transferOwnership(_creator);
    // TODO hardcoded for now
    // TODO all subList calls assume a 1:1 relationship right now!
    _creatorFeePerBlock = 1;

    _stateUpdated = _currentBlock();
  }

  function getVersion() override external pure returns (string memory) {
    return "CreatorVault.v1";
  }

  // TODO change to public?
  function getCreatorFeePerBlock() public view returns (uint) {
    return _creatorFeePerBlock;
  }

  function getActiveSubscriptions() public view returns (uint) {
    return subList.activeSubscriptions;
  }

  function getToken() public view returns (IERC20) {
    return _token;
  }

  function getValues() public view returns (
    string memory version,
    address addr,
    address owner,
    IERC20 token,
    uint activeSubscriptions,
    uint creatorClaimable
  ) {
    version = this.getVersion();
    addr = address(this);
    token = this.getToken();
    activeSubscriptions = this.getActiveSubscriptions();
    owner = this.owner();
    creatorClaimable = this.creatorEarnings();
  }

  // updates state of contract
  // calculates creator claims
  // updates sublist by dropping all expired nodes
  function updateState() public returns (bool) {
    require(_stateUpdated <= _currentBlock());
    if (_stateUpdated == _currentBlock()) {
      // do not update multiple times within same block
      return false;
    }

    (bool listNotEmpty, , ) = subList.head();
    if (!listNotEmpty) {
      _stateUpdated = _currentBlock();
      return true;
    }

    // update subscription list => how many subs did end?
    // update sub counter
    // update creator claimable earnings

    (, uint _creatorEarnings) = _getStateUpdate();

    // actually update state
    _claimableEarnings += _creatorEarnings;

    // clean up sub list
    (bool headExists, uint head, uint value) = subList.head();
    while (headExists && head <= _currentBlock()) {
      subList.remove(head, value);
      (headExists, head, value) = subList.head();
    }

    _stateUpdated = _currentBlock();
    return true;
  }


  /**
    what are the changes from previous to current state?
  */
  function _getStateUpdate() private view returns (uint _subsEnded,
                                                   uint _creatorEarnings) {

    (bool listNotEmpty, , ) = subList.head();
    if (!listNotEmpty) {
      return (0, 0);
    }

    (bool nodeExists, uint currentNode, uint subsExpiring) = subList.head();
    uint claimedBlock = _stateUpdated;
    uint activeSubs = subList.activeSubscriptions;

    while(nodeExists && currentNode <= _currentBlock()) {
      _creatorEarnings += activeSubs * (currentNode - claimedBlock);

      activeSubs -= subsExpiring;
      claimedBlock = currentNode;
      (nodeExists, currentNode, subsExpiring) = subList.next(currentNode);
    }

    _creatorEarnings += activeSubs * (_currentBlock() - claimedBlock);
    _subsEnded = subList.activeSubscriptions - activeSubs;
  }

  /**
    returns the remaining deposit of a user up until the current block.
    Thus the current block is included and paid for.
  */
  function depositOf(address _user) public view returns (uint userBalance) {
    UserDeposit storage userDeposit = deposits[_user];

    uint paidAmount = (_currentBlock() - userDeposit.lastChangeAt) * _creatorFeePerBlock;

    if (paidAmount > userDeposit.amount) {
      return 0;
    }

    return userDeposit.amount - paidAmount;
  }

  function deposit(uint _amount) public returns (bool success){
    // TODO some sort of minimum amount
    // TODO handle deleted node from sublist

    updateState();

    address user = _msgSender();

    // get the tokens first
    _token.safeTransferFrom(user, address(this), _amount);

    // get possible existing deposit or generate empty new one
    UserDeposit storage userDeposit = deposits[user];

    // existing/remaining deposit value
    uint existing = depositOf(user);
    uint newAmount = existing + _amount;

    // TODO handle from last claim/update block
    if (userDeposit.lastChangeAt > 0) {
      // remove existing sub list entry
      uint _endBlock = _subEndBlock(userDeposit.amount, userDeposit.lastChangeAt);
      subList.remove(_endBlock, 1);
    }

    // store initial/updated deposit
    userDeposit.lastChangeAt = _currentBlock();
    userDeposit.amount = newAmount;
    userDeposit.totalAmount += _amount;

    if (userDeposit.initialDepositAt == 0) {
      // never to be changed again
      userDeposit.initialDepositAt = _currentBlock();
    }

    // calculate end of subscription
    // TODO handle updated deposit
    // TODO emit some event and update tests
    // TODO throw exception
    uint endBlock = _subEndBlock(newAmount, _currentBlock());
    (success, , ) = subList.add(endBlock, 1);

    emit UserDeposited(
      user,
      _amount,
      newAmount,
      userDeposit.totalAmount,
      userDeposit.initialDepositAt
    );
  }

  function withdraw(uint _amount) public returns (bool success){

    updateState();

    address user = _msgSender();

    // get possible existing deposit
    UserDeposit storage userDeposit = deposits[user];
    if (userDeposit.initialDepositAt == 0) {
      // the user never did deposit into this vault
      // TODO do we want to throw an exception?
      return false;
    }
    success = true;

    // existing/remaining deposit value
    uint remainingDeposit = depositOf(user);

    require(remainingDeposit >= _amount,
            "Amount to withdraw is larger than remaining deposit");

    uint leftovers = remainingDeposit - _amount;

    // remove current sub from list
    uint _endBlock = _subEndBlock(userDeposit.amount, userDeposit.lastChangeAt);
    subList.remove(_endBlock, 1);

    // update userDeposit state
    userDeposit.lastChangeAt = _currentBlock();
    userDeposit.amount = leftovers;
    userDeposit.totalAmount -= _amount;

    if (leftovers > 0) {
      // if there are tokens left, update to a reduced subscription length
      uint newEndBlock = _subEndBlock(leftovers, _currentBlock());
      if (newEndBlock > _currentBlock()) {
        // TODO function to block adding subs to _currentBlock
        (bool newSubSuccess, , ) = subList.add(newEndBlock, 1);
        success = success && newSubSuccess;
      }
    }

    // finally transfer tokens
    _token.safeTransfer(user, _amount);

    emit UserWithdrew(
      user,
      _amount,
      leftovers,
      userDeposit.totalAmount,
      userDeposit.initialDepositAt
    );
  }

  function _subEndBlock(uint _tokenAmount, uint _depositBlock) private view returns (uint endBlock) {
    // TODO cuts off remaining value => what to do with that?
    uint subBlocks = _tokenAmount / _creatorFeePerBlock;
    endBlock = _depositBlock + subBlocks;
  }

  function creatorEarnings() public view returns (uint earnings) {

    (, uint _creatorEarnings) = _getStateUpdate();

    earnings = _claimableEarnings + _creatorEarnings;
  }

  function creatorWithdraw() public {
    // TODO is there a good case for making this function creator only?
    // transfer earnings of creator to the creator

    // drop nodes from the sublist -> clean up
    // update last claim block
    updateState();
    // transfer tokens

    _token.safeTransfer(owner(), _claimableEarnings);
    _claimableEarnings = 0;
  }

}
