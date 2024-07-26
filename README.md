# Chronomancer
Smart contract endpoint and order-filling bot for fast, Chainlink CCIP-backed transfers.

`NOTE: This code has not been audited, and is intended for testnet use.`

This branch contains a rewrite of Chronomancer for Godot 4.3 using [GodotEthers](https://github.com/Cactoidal/GodotEthersV3).  This version uses a new endpoint contract, and an alpha verison of the ScryPool contract, which allows Chronomancer users to trustlessly pool their tokens when filling orders.  dApps can also gauge bridging capacity by querying Scrypool's availableLiquidity mapping.

This alpha version is close to completion, and I will put out a release once I have deployed the contracts.  Chronomancer will be usable on the 13 public testnets where CCIP is currently available: Avalanche Fuji, BNB Smart Chain Testnet, Ethereum Sepolia, Arbitrum Sepolia, Base Sepolia, Kroma Sepolia, Optimism Sepolia, Wemix Testnet, Gnosis Chiado, Polygon Amoy, Celo Alfajores, Mode Sepolia, and Blast Sepolia.



