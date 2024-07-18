// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FastCCIPEndpoint is CCIPReceiver {

    event OrderFilled(bytes32 messageId, address filler);
    event ReceivedTokens(bytes32 messageId, address token, uint amount);

    error OrderAlreadyFilled();
    error NoRecursionAllowed();
    error OrderAlreadyArrived();

    address immutable ROUTER;

    bool recursionBlock;
  
    // ABI-encoded Any2EVM Messages mapped to filler addresses
    mapping(bytes => address) public orderFillers;
    
    // CCIP Message IDs mapped to booleans
    mapping(bytes32 => bool) messageArrived;

    constructor(address _router) CCIPReceiver(_router) {
        ROUTER = _router;
    }


    // EVM2EVM Messages are pulled from CCIP OnRamps and converted into Any2EVM Messages off-chain.  
    // The local token address is substituted for the remote address, and the filler balance checked 
    // locally before attempting to fill the order.
    
    // _message is the converted Any2EVM Message, now containing the local token address 
    // instead of the remote address.
    function fillOrder(bytes calldata _message) external noReentrancy {

        Client.Any2EVMMessage memory message = abi.decode(_message, (Client.Any2EVMMessage));

        bytes32 messageId = message.messageId;
        
        if (messageArrived[messageId]) {
            revert OrderAlreadyArrived();
        }
        if (orderFillers[_message] != address(0)) {
            revert OrderAlreadyFilled();
        }

        // Extract data for the token transfer
        (address recipient, uint rewardAmount, ) = abi.decode(message.data, (address, uint, bytes));
        address token = message.destTokenAmounts[0].token;
        uint256 amount = message.destTokenAmounts[0].amount;
        // The fill amount accounts for the reward
        amount = amount - rewardAmount;

        // Set the order's fill status using the ABI-encoded Any2EVM Message
        orderFillers[_message] = msg.sender;

        // Send the tokens to the endpoint
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        emit OrderFilled(messageId, msg.sender);

        if (recipient.code.length == 0) {
            IERC20(token).transfer(recipient, amount);
            return;
        }

        // Because the recipient is a contract, the endpoint must first approve a spend allowance
        IERC20(token).approve(address(recipient), amount);

        IERC20(token).transfer(recipient, amount);

        // Send the message containing the data payload
        CCIPReceiver(recipient).ccipReceive(message);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal noReentrancy override {
        require(msg.sender == ROUTER);

        messageArrived[message.messageId] = true;

        address token = message.destTokenAmounts[0].token;
        uint256 amount = message.destTokenAmounts[0].amount;

        emit ReceivedTokens(message.messageId, token, amount);

        (address recipient, , ) = abi.decode(message.data, (address, uint, bytes));

        // Check the order's fill status
        address orderFiller = orderFillers[abi.encode(message)];

        if (orderFiller != address(0)) {
            recipient = orderFiller;
        }

        if (recipient.code.length == 0) {
            IERC20(token).transfer(recipient, amount);
            return;
        }

        IERC20(token).approve(recipient, amount);
        IERC20(token).transfer(recipient, amount);
        CCIPReceiver(recipient).ccipReceive(message);
    }


    // Used by ScryPool or other add-ons to check if an order has been filled
    function checkOrderPathFillStatus(bytes calldata _message, bytes32 _messageId) external view returns (address) {
        if (messageArrived[_messageId]) {
            return address(this);
        }
        return orderFillers[_message];
    }

     modifier noReentrancy() {
        require(!recursionBlock, "No reentrancy");

        recursionBlock = true;
        _;
        recursionBlock = false;
    }


}
