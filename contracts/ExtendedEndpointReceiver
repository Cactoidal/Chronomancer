// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


// A simple example contract demonstrating how a recipient contract can 
// receive Any2EVM messages from the CCIP Fast Endpoint.

contract ExtendedEndpointReceiver is CCIPReceiver {

    event ReceivedTokens(bytes32 messageId, address token, uint amount);

    address immutable ROUTER;
    address immutable CHAINLINK;
  
    mapping(bytes32 => bool) public messageArrived;
    bytes public latestData;

    // Point ROUTER at the endpoint contract
    constructor(address _router, address _link) CCIPReceiver(_router) {
        ROUTER = _router;
        CHAINLINK = _link;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        require(msg.sender == ROUTER);

        messageArrived[message.messageId] = true;

        address token = message.destTokenAmounts[0].token;
        uint256 amount = message.destTokenAmounts[0].amount;

        emit ReceivedTokens(message.messageId, token, amount);

        ( , bytes memory data) = abi.decode(message.data, (address, bytes));

        latestData = data;

    }

}
