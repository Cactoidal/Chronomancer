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

    event ReceivedTokens(bytes32 messageId, address token, uint amount);

    error TooLateToJoinPool();
    error CannotQuitPool();

    address immutable ENDPOINT;
    address immutable CHAINLINK;
  
    struct Filler {
        address fillerAddress;
        uint amount;
        uint poolStartedTimestamp;
        bool orderFilled;
    }

    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => Filler[]))))) orderPathPool;

    // Set the CCIP Fast Endpoint contract as the router
    constructor(address _router, address _link) CCIPReceiver(_router) {
        ENDPOINT = _router;
        CHAINLINK = _link;
    }


    // Creates a pool for a given order if it does not yet exist, or joins
    // an order's existing pool.  When the pool is full, the order will
    // immediately attempt to execute.
    function joinPool(bytes calldata _message, address _localToken) external {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        // The fill amount must account for the fee
        uint256 orderAmount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount / IFastCCIPEndpoint(ENDPOINT).FEE());

        // Check if pool has been created
        Filler[] memory fillers = orderPathPool[messageId][recipient][_localToken][orderAmount][data];
        uint fillerCount = fillers.length;

        if (fillerCount != 0) {
            // Check if pool is too old or has already sent the order
            // As the pool creator, the first filler is checked for order fill status
            Filler memory firstFiller = fillers[0];
            if (block.timestamp > firstFiller.poolStartedTimestamp + 100 || firstFiller.orderFilled) {
                revert TooLateToJoinPool();
            }
        }

        // Determine how many tokens have already been pooled,
        // and how many tokens msg.sender can supply to the pool
        uint totalPooled = 0;
        for (uint i = 0; i < fillerCount; i++) {
            totalPooled += fillers[i].amount;
        }

        uint transferAmount = orderAmount - totalPooled;
        uint fillerBalance = IERC20(_localToken).balanceOf(msg.sender);

        if (fillerBalance < transferAmount) {
            transferAmount = fillerBalance;
        }
        
        // Add msg.sender to the pool
        Filler memory newFiller;
        newFiller.fillerAddress = msg.sender;
        newFiller.amount = transferAmount;
        newFiller.poolStartedTimestamp = block.timestamp;

        orderPathPool[messageId][recipient][_localToken][orderAmount][data].push(newFiller);
        totalPooled += transferAmount;

        // Pool msg.sender's tokens
        IERC20(_localToken).transferFrom(msg.sender, address(this), transferAmount);

        // If the pool is full, immediately fills the order
        if (totalPooled == orderAmount) {
            // Set the first filler's order status
            orderPathPool[messageId][recipient][_localToken][orderAmount][data][0].orderFilled = true;
            // Approve the endpoint's token allowance
            IERC20(_localToken).approve(address(ENDPOINT), orderAmount);
            // Fill the order
            IFastCCIPEndpoint(ENDPOINT).fillOrder(_message, _localToken);
        }

    }

    // Withdraw tokens from an order pool if it is not filled quickly enough
    function quitPool(bytes calldata _message, address _localToken) external {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        // The fill amount must account for the fee
        uint256 orderAmount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount / IFastCCIPEndpoint(ENDPOINT).FEE());

        Filler[] memory fillers = orderPathPool[messageId][recipient][_localToken][orderAmount][data];
        Filler memory firstFiller = fillers[0];
        uint fillerCount = fillers.length;

        // Check if enough time has elapsed and that the order has not been filled
        if (block.timestamp < firstFiller.poolStartedTimestamp + 100 || firstFiller.orderFilled) {
            revert CannotQuitPool();
        }

        // Find msg.sender's address, set token amount to 0, and withdraw tokens
        for (uint i = 0; i < fillerCount; i++) {
            if (fillers[i].fillerAddress == msg.sender) {
                uint transferAmount = fillers[i].amount;
                orderPathPool[messageId][recipient][_localToken][orderAmount][data][i].amount = 0;
                IERC20(_localToken).transfer(msg.sender, transferAmount);
            }
        }

    }

    // The Endpoint will send tokens along with the Any2EVM CCIP message
    // that will be used to distribute the tokens to all fillers in the order's pool
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        require(msg.sender == ENDPOINT);

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));

        address token = message.destTokenAmounts[0].token;
        uint256 orderAmount = message.destTokenAmounts[0].amount;

        emit ReceivedTokens(message.messageId, token, orderAmount);

        uint FEE = IFastCCIPEndpoint(ENDPOINT).FEE();
        uint totalReward = orderAmount / FEE;
        uint poolAmount = orderAmount - totalReward;

        Filler[] memory fillers = orderPathPool[messageId][recipient][token][orderAmount - (totalReward)][data];
        uint fillerCount = fillers.length;

        // Fillers receive their proportionate share 
        for (uint i = 0; i < fillerCount; i++) {
            uint percent = poolAmount / fillers[i].amount;
            uint transferAmount = fillers[i].amount + (totalReward / percent);
            IERC20(token).transfer(fillers[i].fillerAddress, transferAmount);
        }

    }


}
