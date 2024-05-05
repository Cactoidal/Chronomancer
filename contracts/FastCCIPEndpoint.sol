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
    event ReceivedTokens(bytes32 messageId, address token, uint amount);

    error OrderPathAlreadyFilled();
    error NoRecursionAllowed();
    error OrderAlreadyArrived();

    address immutable ROUTER;
    address immutable CHAINLINK;

    //uint256 constant FEE = 1000000000000000;
    // For testing:
    uint256 constant FEE = 0;

    // An order path consists of:
    // CCIP message ID => Recipient Address => Token Address => Token Amount => Data => Filler Address
    mapping(bytes32 => mapping(address => mapping(address => mapping(uint256 => mapping(bytes => address))))) filledOrderPaths;

    mapping(bytes32 => bool) messageArrived;

    constructor(address _router, address _link) CCIPReceiver(_router) {
        ROUTER = _router;
        CHAINLINK = _link;
    }

    Internal.EVM2EVMMessage public testMessage;
    
    // Not compatible with tax-on-transfer tokens; could perhaps be toggled?
    // For now only use standard ERC20 tokens.  Special cases can be added later.
    // Custom endpoints can also define their own logic
    function fillOrder(bytes calldata _message, address _local_token) external {

        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        //address token = message.tokenAmounts[0].token;
        address token = _local_token;

        // The submitted amount must include the fee (0.1%)
        uint amount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount * FEE);
       
        if (messageArrived[messageId]) {
            revert OrderAlreadyArrived();
        }
        if (filledOrderPaths[messageId][recipient][token][amount][data] != address(0)) {
            revert OrderPathAlreadyFilled();
        }
        filledOrderPaths[messageId][recipient][token][amount][data] = msg.sender;

        IERC20(token).transferFrom(msg.sender, recipient, amount);

        emit OrderFilled(messageId);
        if (recipient.code.length == 0) {//|| !_recipient.supportsInterface(type(CCIPReceiver).interfaceId)) {
            return;
        }

        // Should the unadulterated destTokenAmounts value be sent, or should it include the fee?
        // In the event of an unfilled order, the original message is sent.  So I lean
        // toward leaving it alone.
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

        messageArrived[message.messageId] = true;

        address token = message.destTokenAmounts[0].token;
        uint256 amount = message.destTokenAmounts[0].amount;

        emit ReceivedTokens(message.messageId, token, amount);

        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));

        address orderFiller = filledOrderPaths[message.messageId][recipient][token][amount - (amount * FEE)][data];

        if (orderFiller != address(0)) {
            IERC20(token).transfer(orderFiller, amount);
        }
        else {
            if (recipient == address(this)) {
                revert NoRecursionAllowed();
            }
            // Do I need to potentially approve sending tokens in the event that the recipient is a contract?
            // if (recipient.code.length == 0) {
            // IERC20(token).approve(address(this), amount);
            // }
           
            IERC20(token).transfer(recipient, amount);
            if (recipient.code.length == 0) {//|| !_recipient.supportsInterface(type(CCIPReceiver).interfaceId)) {
            return;
        }
            CCIPReceiver(recipient).ccipReceive(message);
        }

    }

    // Used by bots to determine order validity off-chain before submitting a transaction
    function filterOrder(bytes calldata _message, address _endpoint, address _filler, address[] calldata _localTokenList, address[] calldata _remoteTokenList, uint256[] calldata _tokenMinimums) public view returns (address) {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        address receiver = message.receiver;
        address token = message.tokenAmounts[0].token;
        (address recipient, ) = abi.decode(message.data, (address, bytes));

        // Check that the endpoint is the target and that no recursion takes place
        if (receiver != _endpoint || receiver == recipient) {
            return address(0);
        }
        
        // Check EVM2EVM message for monitored remote token, then check the balance and minimum 
        // of the matching local token
        for (uint i = 0; i < _remoteTokenList.length; i++) {
            if (token == _remoteTokenList[i]) {
                if (message.tokenAmounts[0].amount <= IERC20(_localTokenList[i]).balanceOf(_filler)) {
                    if (message.tokenAmounts[0].amount >= _tokenMinimums[i]) {
                        return _localTokenList[i];
                        }
                    }
                }
            }
        
        // Return invalid if not all criteria are met
        return address(0);

    }


    function isOrderPathFilled(bytes calldata _message) public view returns (bool) {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        bytes32 messageId = message.messageId;
        (address recipient, bytes memory data) = abi.decode(message.data, (address, bytes));
        address token = message.tokenAmounts[0].token;

        // The submitted amount must include the fee (0.1%)
        uint amount = message.tokenAmounts[0].amount - (message.tokenAmounts[0].amount * FEE);
       
        if (filledOrderPaths[messageId][recipient][token][amount][data] != address(0)) {
            return true;
        }
        else {
            return false;
        }
    }

}
