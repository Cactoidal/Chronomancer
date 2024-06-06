// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFastCCIPEndpoint {

function fillOrder(bytes calldata) external;

function checkOrderPathFillStatus(bytes calldata) external view returns (address);

}
