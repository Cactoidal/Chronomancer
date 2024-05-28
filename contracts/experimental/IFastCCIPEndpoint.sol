// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFastCCIPEndpoint {

function fillOrder(bytes calldata, address) external;

function FEE() external view returns (uint);

}
