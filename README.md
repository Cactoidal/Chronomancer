# Chronomancer
Smart contract endpoint and order-filling bot for fast, Chainlink CCIP-backed transfers.

`NOTE: This code has not been audited, and is intended for testnet use.`

This branch contains a rewrite of Chronomancer for Godot 4.3 using [GodotEthers](https://github.com/Cactoidal/GodotEthersV3).  This version uses a new endpoint contract, and an alpha verison of the ScryPool contract, which allows Chronomancer users to trustlessly pool their tokens when filling orders.  dApps can also gauge fast-bridging capacity by querying Scrypool's `availableLiquidity` mapping.

This alpha version is close to completion, and I will put out a release once I have deployed the contracts.  Chronomancer will be usable on the 13 public testnets where CCIP is currently available: Avalanche Fuji, BNB Smart Chain Testnet, Ethereum Sepolia, Arbitrum Sepolia, Base Sepolia, Kroma Sepolia, Optimism Sepolia, Wemix Testnet, Gnosis Chiado, Polygon Amoy, Celo Alfajores, Mode Sepolia, and Blast Sepolia.


## Usage

### Chronomancer Providers

Chronomancer providers monitor CCIP OnRamp contracts on sender chains, filter EVM2EVM messages, and provide instant token transfers on destination chains, in exchange for a fee.  As a Chronomancer provider, you can decide which tokens and networks you want to serve, and which networks you want to monitor for incoming messages.

Click the `New Token Lane` button to bring up the lane form, where you can enter:

* Local Network (the network where you will provide fast transfers)

* Local Token (the address of the token you will be transferring; naturally, you must have a balance to provide fast transfers)

* Remote Networks and Tokens (the networks you will monitor for incoming messages, and the contract addresses of the token on those networks)

* Minimum Transfer (the smallest token transfer you are willing to provide)

* Minimum Reward Percent (the lowest percentage of a token transfer you are willing to accept as a reward)

* Maximum Gas Fee (the highest gas fee you are willing to pay for the minimum possible transfer.  This is a "base limit" and will be multiplied by the ratio of transferAmount / minimumTransfer)

* Flat Rate Threshold (an optional parameter defining the minimum reward you are willing to take, even if the reward percentage is lower than the minimum)

After creating your token lane, you must deposit the token into the ScryPool contract.  Click the `Deposit` button, then `Start Monitoring`.  CCIP messages detected on monitored networks will be matched against the criteria you've set, and you will automatically fill the order whenever a match is found.

If you fill the order in its entirety, CCIP will return your tokens automatically once finality time on the sender chain has been reached, and the CCIP message resolves.  If you filled the order as part of a collective pool, you will instead need to claim your tokens manually once the CCIP message has arrived.

This can be done by clicking the `Manage Lane` button, and then `Check For Pending Rewards`.  If there are any rewards waiting, they will be claimed automatically, and added to your deposited token balance.


### Chronomancer Users

To use Chronomancer with your dApp, you must follow these rules when formatting an `EVM2AnyMessage`:

* The `receiver` must be the endpoint contract on the destination chain.

* The `data` payload must be ABI-encoded bytes containing the following values: the intended `recipient` address, which can be a user or an adapter contract (see below); the uint256 `fee`, which should be some small, reasonable percentage of the transfer amount; and some ABI-encoded `bytes`, which can contain any arbitrary data.

* Your `EVMExtraArgs` must define a `gasLimit` of at least 280000.  If your message contains data that must be passed to another contract, make sure you raise the gas limit accordingly.

Chronomancer can pass data along with tokens, which means your dApp can use an adapter contract for receiving the tokens and data, and use these to execute an instruction (such as a swap).

If your dApp needs an estimate of the available liquidity for fast transfers, you can query the `availableLiquidity` mapping on the destination chain's ScryPool contract.  

Note that this is not 100% guaranteed to be accurate (for instance, someone could deposit tokens, but not actually run their Chronomancer bot; or someone could be filling orders without using ScryPool).

If a transfer is initiated to the endpoint, but no fast-transfer liquidity for the token is available, the order will still execute normally once finality on the sender network is reached, and the CCIP message arrives at the endpoint.
