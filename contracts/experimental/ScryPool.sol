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

    struct orderPool {
        fillStatus status;
        bool rewardsPending;
        uint timestamp;
        uint totalPooled;
        mapping(address => uint) fillerAmounts;
    }

    mapping(bytes => orderPool) orderPools;

    // ScryPool tracks pooled token balances deposited on the contract,
    // to allow easy querying of available capacity.
    mapping(address => uint) public availableLiquidity;

    // To participate in ScryPool, providers stake their tokens on the contract.
    // Claimed rewards are added to a provider's staked balance.
    mapping(address => mapping(address => uint)) public userStakedTokens;

    bool reentrancyBlock;


    // Set the CCIP Fast Endpoint contract as the router
    constructor(address _endpoint) CCIPReceiver(_endpoint) {
        ENDPOINT = _endpoint;
    }


    function depositTokens(address _token, uint _amount) external noReentrancy {
        userStakedTokens[msg.sender][_token] += _amount;
        availableLiquidity[_token] += _amount;
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    }


    function withdrawTokens(address _token) external noReentrancy {
        uint transferAmount = userStakedTokens[msg.sender][_token];
        userStakedTokens[msg.sender][_token] = 0;
        availableLiquidity[_token] -= transferAmount;

        // Check if msg.sender is a contract
        if (msg.sender.code.length != 0) {
            IERC20(_token).approve(msg.sender, transferAmount);
        }

        IERC20(_token).transfer(msg.sender, transferAmount);
    }


    function joinPool(bytes calldata _message) external noReentrancy {
        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        bytes32 messageId = message.messageId;
        ( , uint feeDivisor, ) = abi.decode(message.data, (address, uint, bytes));
        uint orderAmount = message.destTokenAmounts[0].amount;
        address token = message.destTokenAmounts[0].token;
        // The fill amount must account for the fee
        orderAmount = orderAmount - (orderAmount / feeDivisor);

        orderPool storage order = orderPools[_message];
        // Get the pool info
        uint totalPooled = order.totalPooled;
        uint poolStartedTimestamp = order.timestamp;

        // Check if pool exists; if not, set the timestamp
        if (poolStartedTimestamp == 0) {
            order.timestamp = block.timestamp;
        }
        // Check if pool is stale or has already been filled
        else if (block.timestamp > poolStartedTimestamp + 100 || totalPooled == orderAmount) {
            revert TooLateToJoinPool();
        }

        // Determine how many tokens have already been pooled,
        // and how many tokens msg.sender can supply to the pool
        uint transferAmount = orderAmount - totalPooled;
        uint fillerBalance = userStakedTokens[msg.sender][token];

        if (fillerBalance < transferAmount) {
            transferAmount = fillerBalance;
        }
        // Add msg.sender to the pool
        order.fillerAmounts[msg.sender] += transferAmount;

        // Update the total pooled amount
        totalPooled += transferAmount;
        order.totalPooled = totalPooled;
      
        // Pool msg.sender's tokens
        availableLiquidity[token] -= transferAmount;
        userStakedTokens[msg.sender][token] -= transferAmount;

        // If the pool is full, immediately attempt to fill the order.  Then set the order fill status
        if (totalPooled == orderAmount) {

            if (IFastCCIPEndpoint(ENDPOINT).checkOrderPathFillStatus(_message, messageId) == address(0)) {
                // Approve the endpoint's token allowance
                IERC20(token).approve(address(ENDPOINT), orderAmount);
                // Fill the order
                IFastCCIPEndpoint(ENDPOINT).fillOrder(_message);

                order.status = fillStatus.SUCCESS;
                emit FilledOrder(messageId);
                }
            else {
                order.status = fillStatus.FAILED;
                emit FailedToFillOrder(messageId);
                }

            }

        }

    function quitPool(bytes calldata _message) external noReentrancy {
        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        address token = message.destTokenAmounts[0].token;
    
        orderPool storage order = orderPools[_message];
        uint poolStartedTimestamp = order.timestamp;
        fillStatus orderStatus = order.status;

        // Check if order successfully completed
        if (orderStatus == fillStatus.SUCCESS){
            revert CannotQuitPool();
        }
        // Check if enough time has elapsed or if the order has failed
        if (block.timestamp > poolStartedTimestamp + 100 || orderStatus == fillStatus.FAILED) {
            uint transferAmount = order.fillerAmounts[msg.sender];
            order.fillerAmounts[msg.sender] = 0;
            availableLiquidity[token] += transferAmount;
            userStakedTokens[msg.sender][token] += transferAmount;
        }
        else {
            revert CannotQuitPool();
        }

    }

        // The Endpoint will send tokens along with the Any2EVM CCIP message
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        require(msg.sender == ENDPOINT);

        bytes32 messageId = message.messageId;

        orderPools[abi.encode(message)].rewardsPending = true;
        emit MessageReceived(messageId);

    }


    // Participants in a successfully filled order can claim tokens once the CCIP message has arrived
    function claimOrderReward(bytes calldata _message) external noReentrancy {
        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        (, uint feeDivisor, ) = abi.decode(message.data, (address, uint, bytes));
        uint orderAmount = message.destTokenAmounts[0].amount;
        address token = message.destTokenAmounts[0].token;

        uint totalReward = orderAmount / feeDivisor;
        uint poolAmount = orderAmount - totalReward;

        orderPool storage order = orderPools[_message];

        // Check if CCIP message has arrived
        if (!order.rewardsPending) {
            revert MessageNotReceived();
        }
        
        // Calculate order filler's proportionate share
        uint contributedAmount = order.fillerAmounts[msg.sender];

        uint percent = poolAmount / contributedAmount;
        uint transferAmount = contributedAmount + (totalReward / percent);
        // Set contribution amount to 0
        order.fillerAmounts[msg.sender] = 0;
        // Disburse tokens
        availableLiquidity[token] += transferAmount;
        userStakedTokens[msg.sender][token] += transferAmount;

        emit RewardDisbursed(msg.sender, transferAmount);

    }



    modifier noReentrancy() {
        require(!reentrancyBlock, "No reentrancy");

        reentrancyBlock = true;
        _;
        reentrancyBlock = false;
    }


}
