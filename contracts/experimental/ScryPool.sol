// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IFastCCIPEndpoint.sol";

// Individual bots in the current system are limited by their token supply when filling orders,
// which restricts the maximum size of orders.
// ScryPool allows bots to trustlessly pool their tokens, enabling them to collectively fill bigger orders.

// To work, the Fast CCIP Endpoint will need to be reconfigured to check whether the order-filling address
// is a contract, and send the Any2EVM message along with any tokens.

contract ScryPool is CCIPReceiver {

    event FilledOrder(bytes32);
    event FailedToFillOrder(bytes32);
    event MessageReceived(bytes32);
    event RewardDisbursed(address, uint);

    error TooLateToJoinPool();
    error CannotQuitPool();
    error MessageNotReceived();

    address immutable ENDPOINT;

    enum fillStatus {
        PENDING,
        SUCCESS,
        FAILED
    }

    // ABI-encoded Any2EVMMessage => Filler Address => Contributed Amount
    mapping(bytes => mapping(address => uint)) pooledOrderFillers;
  
    mapping(bytes => uint) orderPoolStartedTimestamp;

    mapping(bytes => fillStatus) orderPoolStatus;
    
    mapping(bytes => uint) orderPoolTotals;
   
    mapping(bytes => bool) rewardsPending;

    bool reentrancyBlock;

    // Set the CCIP Fast Endpoint contract as the router
    constructor(address _endpoint) CCIPReceiver(_endpoint) {
        ENDPOINT = _endpoint;
    }

    // Create a pool for a given order if it does not yet exist, or join
    // an order's existing pool.  When the pool is full, the order will
    // immediately attempt to execute.
    // _message is an Any2EVM message converted from an OnRamp EVM2EVM message
    function joinPool(bytes calldata _message) external noReentrancy {
        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        bytes32 messageId = message.messageId;
        ( , uint feeDivisor, ) = abi.decode(message.data, (address, uint, bytes));
        uint orderAmount = message.destTokenAmounts[0].amount;
        address token = message.destTokenAmounts[0].token;
        // The fill amount must account for the fee
        orderAmount = orderAmount - (orderAmount / feeDivisor);

        // Get the pool info
        uint totalPooled = orderPoolTotals[_message];
        uint poolStartedTimestamp = orderPoolStartedTimestamp[_message];

        // Check if pool exists; if not, set the timestamp
        if (poolStartedTimestamp == 0) {
            orderPoolStartedTimestamp[_message] = block.timestamp;
        }
        // Check if pool is stale or has already been filled
        else if (block.timestamp > poolStartedTimestamp + 100 || totalPooled == orderAmount) {
            revert TooLateToJoinPool();
        }

        // Determine how many tokens have already been pooled,
        // and how many tokens msg.sender can supply to the pool
        uint transferAmount = orderAmount - totalPooled;
        uint fillerBalance = IERC20(token).balanceOf(msg.sender);

        if (fillerBalance < transferAmount) {
            transferAmount = fillerBalance;
        }
        // Add msg.sender to the pool
        pooledOrderFillers[_message][msg.sender] += transferAmount;

        // Update the total pooled amount
        totalPooled += transferAmount;
        orderPoolTotals[_message] = totalPooled;
      
        // Pool msg.sender's tokens
        IERC20(token).transferFrom(msg.sender, address(this), transferAmount);

        // If the pool is full, immediately attempt to fill the order.  Then set the order fill status
        if (totalPooled == orderAmount) {

            if (IFastCCIPEndpoint(ENDPOINT).checkOrderPathFillStatus(_message) == address(0)) {
                // Approve the endpoint's token allowance
                IERC20(token).approve(address(ENDPOINT), orderAmount);
                // Fill the order
                IFastCCIPEndpoint(ENDPOINT).fillOrder(_message);

                // Probably want to change error-handling on endpoint's fillOrder()
                // so it's possible to handle reversion

                orderPoolStatus[_message] = fillStatus.SUCCESS;
                emit FilledOrder(messageId);
                }
            else {
                orderPoolStatus[_message] = fillStatus.FAILED;
                emit FailedToFillOrder(messageId);
                }

            }

        }

    // Withdraw tokens from an order pool if it has not filled quickly enough, or failed to fill
    function quitPool(bytes calldata _message) external noReentrancy {
        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        address token = message.destTokenAmounts[0].token;
    
        uint poolStartedTimestamp = orderPoolStartedTimestamp[_message];
        fillStatus orderStatus = orderPoolStatus[_message];

        // Check if order successfully completed
        if (orderStatus == fillStatus.SUCCESS){
            revert CannotQuitPool();
        }
        // Check if enough time has elapsed or if the order has failed
        if (block.timestamp > poolStartedTimestamp + 100 || orderStatus == fillStatus.FAILED) {
            uint transferAmount = pooledOrderFillers[_message][msg.sender];
            pooledOrderFillers[_message][msg.sender] = 0;
            IERC20(token).transfer(msg.sender, transferAmount);
        }
        else {
            revert CannotQuitPool();
        }

    }

    // The Endpoint will send tokens along with the Any2EVM CCIP message
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        require(msg.sender == ENDPOINT);

        bytes32 messageId = message.messageId;
   
        rewardsPending[abi.encode(message)] = true;
        emit MessageReceived(messageId);

    }

    // Participants in a successfully filled order can withdraw tokens once the CCIP message has arrived
    function withdrawOrderReward(bytes calldata _message) external noReentrancy {
        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        (, uint feeDivisor, ) = abi.decode(message.data, (address, uint, bytes));
        uint orderAmount = message.destTokenAmounts[0].amount;
        address token = message.destTokenAmounts[0].token;

        uint totalReward = orderAmount / feeDivisor;
        uint poolAmount = orderAmount - totalReward;

        // Check if CCIP message has arrived
        if (!rewardsPending[_message]) {
            revert MessageNotReceived();
        }
        
        // Calculate order filler's proportionate share
        uint contributedAmount = pooledOrderFillers[_message][msg.sender];

        uint percent = poolAmount / contributedAmount;
        uint transferAmount = contributedAmount + (totalReward / percent);
        // Set contribution amount to 0
        pooledOrderFillers[_message][msg.sender] = 0;
        // Disburse tokens
        IERC20(token).transfer(msg.sender, transferAmount);

        emit RewardDisbursed(msg.sender, transferAmount);

    }

    modifier noReentrancy() {
        require(!reentrancyBlock, "No reentrancy");

        reentrancyBlock = true;
        _;
        reentrancyBlock = false;
    }


}
