// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract FastCCIPEndpoint is CCIPReceiver {

    event OrderFilled(bytes32 messageId);
    event MessageReceived(bytes32 messageId);
    error OrderPathAlreadyFilled();

    address immutable ROUTER;
    address immutable CHAINLINK;

    //uint256 constant FEE = 1000000000000000;
    // For testing:
    uint256 constant FEE = 0;

    // An order path consists of:
    // CCIP message ID => Recipient Address => Token Address => Token Amount => Data => Filler Address
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => address))))) filledOrderPaths;

    constructor(address _router, address _link) CCIPReceiver(_router) {
        ROUTER = _router;
        CHAINLINK = _link;
    }

    
    // Not compatible with tax-on-transfer tokens; could perhaps be toggled?
    function fillOrder(bytes calldata _message) external {

        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        address token = message.tokenAmounts[0].token;

        // The submitted amount must include the fee (0.1%)
        uint amount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount * FEE);
       
        if (filledOrderPaths[messageId][recipient][token][amount][data] != address(0)) {
            revert OrderPathAlreadyFilled();
        }
        filledOrderPaths[messageId][recipient][token][amount][data] = msg.sender;
        IERC20(token).transferFrom(msg.sender, recipient, amount);
        emit OrderFilled(messageId);
        if (recipient.code.length == 0) {//|| !_recipient.supportsInterface(type(CCIPReceiver).interfaceId)) {
            return;
        }

    
        Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
            messageId: message.messageId,
            sourceChainSelector: message.sourceChainSelector,
            sender: abi.encode(message.sender),
            data: abi.encode(message.data),
            destTokenAmounts: message.tokenAmounts
            });


        CCIPReceiver(recipient).ccipReceive(ccipMessage);
    }

    // Right now only compatible with one token, due to the nature of order paths.
    // Could be reconfigured to work with multiple tokens, multiple recipients, and multiple data objects
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        require(msg.sender == ROUTER);
        emit MessageReceived(message.messageId);

        address token = message.destTokenAmounts[0].token;
        uint256 amount = message.destTokenAmounts[0].amount;

        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));

        address orderFiller = filledOrderPaths[message.messageId][recipient][token][amount - (amount * FEE)][data];

        if (orderFiller != address(0)) {
            IERC20(token).transfer(orderFiller, amount);
        }
        else {
            IERC20(token).transfer(recipient, amount);
            if (recipient.code.length == 0) {//|| !_recipient.supportsInterface(type(CCIPReceiver).interfaceId)) {
            return;
        }
            CCIPReceiver(recipient).ccipReceive(message);
        }

    }


    function filterOrder(bytes calldata _message, address _endpoint, address _token) public pure returns (address, uint256) {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));
        address receiver = message.receiver;
        address token = message.tokenAmounts[0].token;
        if (receiver != _endpoint) {
            return (address(0), 0);
        }
        if (token != _token) {
            return (address(0), 0);
        }
        return (receiver, message.tokenAmounts[0].amount);

    }


}
