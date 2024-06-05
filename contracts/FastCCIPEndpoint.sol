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
    address immutable CHAINLINK;

    uint256 constant public FEE = 1000;
    bool recursionBlock;
  
    // ABI-encoded Any2EVM Messages mapped to filler addresses
    mapping(bytes => address) public orderFillers;
    
    mapping(bytes32 => bool) messageArrived;

    constructor(address _router, address _link) CCIPReceiver(_router) {
        ROUTER = _router;
        CHAINLINK = _link;
    }

    // Convert the EVM2EVM Message to Any2EVM Message off-chain
    function retrieveAny2EVM(bytes calldata _message, address _localToken) external pure returns (bytes memory) {
        Internal.EVM2EVMMessage memory message = abi.decode(_message, (Internal.EVM2EVMMessage));

        Client.EVMTokenAmount[] memory tokenAmounts;
        tokenAmounts[0].token = _localToken;
        tokenAmounts[0].amount = message.tokenAmounts[0].amount;

        Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
            messageId: message.messageId,
            sourceChainSelector: message.sourceChainSelector,
            sender: abi.encode(message.sender),
            data: abi.encode(message.data),
            destTokenAmounts: tokenAmounts
            });

        return abi.encode(ccipMessage);
    }
    
    // _message is the converted Any2EVM Message, now containing the local token address instead of the remote address.
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
        (address recipient, ) = abi.decode(message.data, (address, bytes));
        address token = message.destTokenAmounts[0].token;
        uint256 amount = message.destTokenAmounts[0].amount;
        // The fill amount accounts for the fee
        amount = amount - (amount / FEE);

        // Set the order's fill status using the ABI-encoded Any2EVM Message
        orderFillers[_message] = msg.sender;

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        emit OrderFilled(messageId, msg.sender);

        if (recipient.code.length == 0) {
            IERC20(token).transfer(recipient, amount);
            return;
        }

        // Because the recipient is a contract, the endpoint must first approve a spend allowance
        IERC20(token).approve(address(recipient), amount);

        IERC20(token).transfer(recipient, amount);

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

        (address recipient, ) = abi.decode(message.data, (address, bytes));

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

    // Used by ScryPool or other add-ons to check if an order has been filled
    function checkOrderPathFillStatus(bytes calldata _message) external view returns (address) {
        return orderFillers[_message];
    }

     modifier noReentrancy() {
        require(!recursionBlock, "No reentrancy");

        recursionBlock = true;
        _;
        recursionBlock = false;
    }


}
