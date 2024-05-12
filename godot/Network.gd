extends Node

var network_info

var default_network_info = {
	
	"Ethereum Sepolia": 
		{
		"chain_id": 11155111,
		"rpc": "https://endpoints.omniatech.io/v1/eth/sepolia/public",
		"gas_balance": "0", 
		"onramp_contracts": ["0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e", "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d", "0x2B70a05320cB069e0fB55084D402343F832556E7"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Arbitrum Sepolia",
					"contract": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d"
				},
				{
					"network": "Base Sepolia",
					"contract": "0x2B70a05320cB069e0fB55084D402343F832556E7"
				}
			
		],
		"endpoint_contract": "0xD9E254783C240ece646C00e2D3c1Fb6Eb0215749",
		"monitored_tokens": [], 
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"latest_block": "latest",
		"order_processor": null,
		"scan_url": "https://sepolia.etherscan.io/",
		"logo": "res://assets/Ethereum.png"
		},
		
	"Arbitrum Sepolia": 
		{
		"chain_id": 421614,
		"rpc": "https://sepolia-rollup.arbitrum.io/rpc",
		"gas_balance": "0", 
		"onramp_contracts": ["0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9", "0x701Fe16916dd21EFE2f535CA59611D818B017877", "0x7854E73C73e7F9bb5b0D5B4861E997f4C6E8dcC6"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x701Fe16916dd21EFE2f535CA59611D818B017877"
				},
				{
					"network": "Base Sepolia",
					"contract": "0x7854E73C73e7F9bb5b0D5B4861E997f4C6E8dcC6"
				}
			
		],
		"endpoint_contract": "0x69487b0e0CF57Ad6b4339cda70a45b4aDB8eef08",
		"monitored_tokens": [],
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"latest_block": "latest",
		"order_processor": null,
		"scan_url": "https://sepolia.arbiscan.io/",
		"logo": "res://assets/Arbitrum.png"
		},
		
	"Optimism Sepolia": {
		"chain_id": 11155420,
		"rpc": "https://sepolia.optimism.io",
		"gas_balance": "0", 
		"onramp_contracts": ["0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a", "0x1a86b29364D1B3fA3386329A361aA98A104b2742", "0xe284D2315a28c4d62C419e8474dC457b219DB969"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a"
				},
				{
					"network": "Arbitrum Sepolia",
					"contract": "0x1a86b29364D1B3fA3386329A361aA98A104b2742"
				},
				{
					"network": "Base Sepolia",
					"contract": "0xe284D2315a28c4d62C419e8474dC457b219DB969"
				}
			
		],
		"endpoint_contract": "0x8b98E266f5983084Fe5813E3d729391056c15692",
		"monitored_tokens": [],
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"latest_block": "latest",
		"order_processor": null,
		"scan_url": "https://sepolia-optimism.etherscan.io/",
		"logo": "res://assets/Optimism.png"
	},
	
	"Base Sepolia": {
		"chain_id": 84532,
		"rpc": "https://sepolia.base.org",
		"gas_balance": "0", 
		"onramp_contracts": ["0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea", "0x58622a80c6DdDc072F2b527a99BE1D0934eb2b50", "0x3b39Cd9599137f892Ad57A4f54158198D445D147"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea"
				},
				{
					"network": "Arbitrum Sepolia",
					"contract": "0x58622a80c6DdDc072F2b527a99BE1D0934eb2b50"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x3b39Cd9599137f892Ad57A4f54158198D445D147"
				}
			
		],
		"endpoint_contract": "0xC3E1D898D09511AD47842607779985BD95018DE2",
		"monitored_tokens": [],
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"latest_block": "latest",
		"order_processor": null,
		"scan_url": "https://sepolia.basescan.org/",
		"logo": "res://assets/Base.png"
	}
}
