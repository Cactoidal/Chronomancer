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

    // CCIP message ID => Recipient Address => Token Address => Token Amount => Data => Filler Address => Contributed Amount
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => mapping(address => uint)))))) pooledOrderFillers;
    // CCIP message ID => Recipient Address => Token Address => Token Amount => Data => poolStartedTimestamp
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => uint))))) orderPathPoolStarted;
    // CCIP message ID => Recipient Address => Token Address => Token Amount => Data => fillStatus
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => fillStatus))))) orderPathPoolStatus;
    // CCIP message ID => Recipient Address => Token Address => Token Amount => Data => totalPooled
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => uint))))) orderPathPoolTotals;
    
    mapping(bytes32 => bool) rewardsPending;

    // Set the CCIP Fast Endpoint contract as the router
    constructor(address _endpoint) CCIPReceiver(_endpoint) {
        ENDPOINT = _endpoint;
    }

    // Create a pool for a given order if it does not yet exist, or join
    // an order's existing pool.  When the pool is full, the order will
    // immediately attempt to execute.
    function joinPool(bytes calldata _message, address _localToken) external {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        // The fill amount must account for the fee
        uint256 orderAmount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount / IFastCCIPEndpoint(ENDPOINT).FEE());

        // Get the pool info
        uint totalPooled = orderPathPoolTotals[messageId][recipient][_localToken][orderAmount][data];
        uint poolStartedTimestamp = orderPathPoolStarted[messageId][recipient][_localToken][orderAmount][data];

        // Check if pool exists; if not, set the timestamp
        if (poolStartedTimestamp == 0) {
            orderPathPoolStarted[messageId][recipient][_localToken][orderAmount][data] = block.timestamp;
        }
        // Check if pool is stale or has already been filled
        else if (block.timestamp > poolStartedTimestamp + 100 || totalPooled == orderAmount) {
            revert TooLateToJoinPool();
        }

        // Determine how many tokens have already been pooled,
        // and how many tokens msg.sender can supply to the pool
        uint transferAmount = orderAmount - totalPooled;
        uint fillerBalance = IERC20(_localToken).balanceOf(msg.sender);

        if (fillerBalance < transferAmount) {
            transferAmount = fillerBalance;
        }
        // Add msg.sender to the pool
        pooledOrderFillers[messageId][recipient][_localToken][orderAmount][data][msg.sender] = transferAmount;

        // Update the total pooled amount
        totalPooled += transferAmount;
        orderPathPoolTotals[messageId][recipient][_localToken][orderAmount][data] = totalPooled;
      
        // Pool msg.sender's tokens
        IERC20(_localToken).transferFrom(msg.sender, address(this), transferAmount);

        // If the pool is full, immediately attempt to fill the order
        if (totalPooled == orderAmount) {
            // Approve the endpoint's token allowance
            IERC20(_localToken).approve(address(ENDPOINT), orderAmount);
            // Attempt to fill the order, then set the order fill status
            try IFastCCIPEndpoint(ENDPOINT).fillOrder(_message, _localToken) {
                orderPathPoolStatus[messageId][recipient][_localToken][orderAmount][data] = fillStatus.SUCCESS;
                emit FilledOrder(messageId);

            } catch {
                orderPathPoolStatus[messageId][recipient][_localToken][orderAmount][data] = fillStatus.FAILED;
                emit FailedToFillOrder(messageId);
            }
        }

    }

    // Withdraw tokens from an order pool if it has not filled quickly enough, or failed to fill
    function quitPool(bytes calldata _message, address _localToken) external {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        // The fill amount must account for the fee
        uint256 orderAmount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount / IFastCCIPEndpoint(ENDPOINT).FEE());

        uint poolStartedTimestamp = orderPathPoolStarted[messageId][recipient][_localToken][orderAmount][data];
        fillStatus orderStatus = orderPathPoolStatus[messageId][recipient][_localToken][orderAmount][data];

        // Check if order successfully completed
        if (orderStatus == fillStatus.SUCCESS){
            revert CannotQuitPool();
        }
        // Check if enough time has elapsed or if the order has failed
        if (block.timestamp > poolStartedTimestamp + 100 || orderStatus == fillStatus.FAILED) {
            uint transferAmount = pooledOrderFillers[messageId][recipient][_localToken][orderAmount][data][msg.sender];
            pooledOrderFillers[messageId][recipient][_localToken][orderAmount][data][msg.sender] = 0;
            IERC20(_localToken).transfer(msg.sender, transferAmount);
        }
        else {
            revert CannotQuitPool();
        }

    }

    // The Endpoint will send tokens along with the Any2EVM CCIP message
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        require(msg.sender == ENDPOINT);

        bytes32 messageId = message.messageId;

        rewardsPending[messageId] = true;

        emit MessageReceived(messageId);

    }

    // Participants in a successfully filled order can withdraw tokens once the CCIP message has arrived
    function withdrawOrderReward(bytes calldata _message, address _localToken) external {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;

        if (!rewardsPending[messageId]) {
            revert MessageNotReceived();
        }

        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));

        // Calculate order filler's proportionate share
        uint256 orderAmount = message.tokenAmounts[0].amount;
        uint FEE = IFastCCIPEndpoint(ENDPOINT).FEE();
        uint totalReward = orderAmount / FEE;
        
        uint contributedAmount = pooledOrderFillers[messageId][recipient][_localToken][orderAmount][data][msg.sender];

        uint poolAmount = orderAmount - totalReward;
        uint percent = poolAmount / contributedAmount;
        uint transferAmount = contributedAmount + (totalReward / percent);
        // Set contribution amount to 0
        pooledOrderFillers[messageId][recipient][_localToken][orderAmount][data][msg.sender] = 0;
        // Disburse tokens
        IERC20(_localToken).transfer(msg.sender, transferAmount);

        emit RewardDisbursed(msg.sender, transferAmount);

    }
    

}
