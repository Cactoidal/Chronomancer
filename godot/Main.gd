extends Control

var eth_http_request = preload("res://EthRequest.tscn")
var order_processor = preload("res://OrderProcessor.tscn")

var user_address
var header = "Content-Type: application/json"

var networks = ["Ethereum Sepolia", "Arbitrum Sepolia"]

#the ability to add tokens, networks, onramps, and endpoint contracts would be nice

var network_info = {
	
	"Ethereum Sepolia": 
		{
		"chain_id": 11155111,
		"rpc": "https://endpoints.omniatech.io/v1/eth/sepolia/public",
		"gas_balance": "0", 
		"onramp_contracts": ["0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e", "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Arbitrum Sepolia",
					"contract": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0xx69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d"
				}
			
		],
		"endpoint_contract": "0x39E98Ab623cf367462d049aB389E6f3083556dA8",
		"monitored_tokens": [{"token_contract": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05", "token_balance": "0", "minimum": 0.00000001}], #BnM address
		"minimum_gas_threshold": 0,
		"latest_block": 0,
		"order_processor": null
		},
		
	"Arbitrum Sepolia": 
		{
		"chain_id": 421614,
		"rpc": "https://endpoints.omniatech.io/v1/arbitrum/sepolia/public",
		"gas_balance": "0", 
		"onramp_contracts": ["0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9", "0x701Fe16916dd21EFE2f535CA59611D818B017877"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x701Fe16916dd21EFE2f535CA59611D818B017877"
				}
			
		],
		"endpoint_contract": "", #deploy it
		"monitored_tokens": [{"token_contract": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D", "token_balance": "0", "minimum": 0.00000001}], #BnM address
		"minimum_gas_threshold": 0,
		"latest_block": 0,
		"order_processor": null
		},
		
	"Optimism Sepolia": {
		"chain_id": 11155420,
		"rpc": "https://sepolia.optimism.io",
		"gas_balance": "0", 
		"onramp_contracts": ["0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a", "0x1a86b29364D1B3fA3386329A361aA98A104b2742"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a"
				},
				{
					"network": "Arbitrum Sepolia",
					"contract": "0x1a86b29364D1B3fA3386329A361aA98A104b2742"
				}
			
		],
		"endpoint_contract": "", #deploy it
		"monitored_tokens": [{"token_contract": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7", "token_balance": "0", "minimum": 0.00000001}], #BnM address
		"minimum_gas_threshold": 0,
		"latest_block": 0,
		"order_processor": null
	},
	
	"Polygon Mumbai": {},
	"Base Testnet": {}
}

func _ready():
	check_keystore()
	get_address()
	get_gas_balances()
	for network in networks:
		var new_processor = order_processor.instance()
		network_info[network]["order_processor"] = new_processor
		new_processor.network_info = network_info[network].duplicate()
		new_processor.main_script = self
		new_processor.user_address = user_address
		$HTTP.add_child(new_processor)

var log_timer = 1

func _process(delta):
	log_timer -= delta
	if log_timer < 0:
		log_timer = 1
		get_logs()

func get_logs():
	for network in networks:
		perform_ethereum_request(network, "eth_getLogs", [{"fromBlock": "latest", "address": network_info[network]["onramp_contracts"], "topics": ["0xd0c3c799bf9e2639de44391e7f524d229b2b55f5b1ea94b2bf7da42f7243dddd"]}])

func perform_ethereum_request(network, method, params, extra_args={}):
	var rpc = network_info[network]["rpc"]
	
	var http_request = eth_http_request.instance()
	$HTTP.add_child(http_request)
	http_request.network = network
	http_request.request_type = method
	http_request.main_script = self
	http_request.extra_args = extra_args
	http_request.connect("request_completed", http_request, "resolve_ethereum_request")
	
	var tx = {"jsonrpc": "2.0", "method": method, "params": params, "id": 7}
	
	http_request.request(rpc, 
	[header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func resolve_ethereum_request(network, method, get_result, extra_args):
	match method:
		"eth_getBalance": update_balance(network, get_result)
		"eth_blockNumber": update_block_number(network, get_result)
		"eth_getLogs": check_for_ccip_messages(network, get_result)

func check_for_ccip_messages(from_network, get_result):
	if get_result["result"] != []:
		for event in get_result["result"]:
			
			var message = event["data"].right(2)
			var onramp = event["address"]
				
			var onramp_list = network_info[from_network]["onramp_contracts_by_network"].duplicate()
			var to_network
			for network in onramp_list:
				if network["contract"] != onramp:
					network["contract"] = network["contract"].to_lower()
				if network["contract"] == onramp:
					to_network = network["network"]
			
			network_info[to_network]["order_processor"].intake_message(message)
			
func ethereum_request_failed(network, method, extra_args):
	pass

func check_keystore():
	var file = File.new()
	if file.file_exists("user://keystore") != true:
		var bytekey = Crypto.new()
		var content = bytekey.generate_random_bytes(32)
		file.open("user://keystore", File.WRITE)
		file.store_buffer(content)
		file.close()

func get_address():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	user_address = FastCcipBot.get_address(content)
	$Address.text = user_address
	file.close()

func export_key():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	#Copy and paste this string into a wallet importer:
	print(content.hex_encode())

func import_key():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	#Unfortunately Godot 3.5 seems to struggle with hex decode,
	#so I will need to use Rust to get the buffer.

func get_gas_balances():
	for network in networks:
		perform_ethereum_request(network, "eth_getBalance", [user_address, "latest"])

func get_erc20_balance(network, token_contract):
	var chain_id = network_info[network]["chain_id"]
	var rpc = network_info[network]["rpc"]
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.check_token_balance(content, chain_id, rpc, token_contract)
	perform_ethereum_request(network, "eth_call", [{"to": token_contract, "input": calldata}, "latest"], {"function_name": "check_token_balance", "token_contract": token_contract})


#make sure no doubles are possible
func add_monitored_token(network, token_contract, token_balance, endpoint_contract, minimum):
	var new_monitored_token = {
		"token_contract": token_contract,
		"token_balance": token_balance,
		"endpoint_contract": endpoint_contract,
		"minimum": minimum,
	}
	network_info[network]["monitored_tokens"].append(new_monitored_token)


func update_balance(network, get_result):
	var balance = String(get_result["result"].hex_to_int())
	network_info[network]["gas_balance"] = balance
	$GasBalances.get_node(network).text = balance

func update_block_number(network, get_result):
	var latest_block = get_result["result"].hex_to_int()
	network_info[network]["latest_block"] = latest_block

