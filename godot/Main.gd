extends Control

var eth_http_request = preload("res://EthRequest.tscn")
var order_processor = preload("res://OrderProcessor.tscn")
var monitorable_token = preload("res://MonitorableToken.tscn")
var sent_transaction = preload("res://SentTransaction.tscn")

var crystal_ball

var password
var user_address
var header = "Content-Type: application/json"

var networks = ["Ethereum Sepolia", "Arbitrum Sepolia", "Optimism Sepolia"]

var monitorable_tokens = []
var active_monitored_tokens = []

#the ability to add tokens, networks, onramps, and endpoint contracts would be nice
#I may need to be flexible in allowing addition of networks that do not monitor
#onramps of every other chain, nor require that each added network be monitored by
#each other chain

#eventually let's move this data blob somewhere else
# so it's not cluttering the top of this script
var network_info = {}
var default_network_info = {
	
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
		"maximum_gas_fee": "",
		"latest_block": 0,
		"order_processor": null,
		"scan_url": "https://sepolia.etherscan.io/",
		"logo": "res://assets/Ethereum.png"
		},
		
	"Arbitrum Sepolia": 
		{
		"chain_id": 421614,
		"rpc": "https://sepolia-rollup.arbitrum.io/rpc",
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
		"endpoint_contract": "0x1F325786Ed9B347D54BC24c21585239E77f9e466",
		"monitored_tokens": [],
		"minimum_gas_threshold": 0,
		"maximum_gas_fee": "",
		"latest_block": 0,
		"order_processor": null,
		"scan_url": "https://sepolia.arbiscan.io/",
		"logo": "res://assets/Arbitrum.png"
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
		"endpoint_contract": "0x2e0d90fD5C983a5a76f5AB32698Db396Df066491",
		"monitored_tokens": [{"token_contract": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7", "token_balance": "0", "minimum": 0.00000001}], #BnM address
		"minimum_gas_threshold": 0,
		"maximum_gas_fee": "",
		"latest_block": 0,
		"order_processor": null,
		"scan_url": "https://sepolia-optimism.etherscan.io/",
		"logo": "res://assets/Optimism.png"
	},
	
	"Polygon Mumbai": {},
	"Base Testnet": {}
}


#func _ready():
func initialize():
	get_address()
	#get_gas_balances()	
	crystal_ball = get_parent().get_node("ChronomancerLogo/LogoPivot")
	$LoadSavedTokens.connect("pressed", self, "load_saved_tokens")
	for network in networks:
		var new_processor = order_processor.instance()
		network_info[network]["order_processor"] = new_processor
		new_processor.network = network
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
	var network_list = []
	
	for token in active_monitored_tokens:
		for network in token["monitored_networks"].keys():
			if !network in network_list:
				network_list.append(network)
	
	for network in network_list:
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
		"eth_call": check_endpoint_allowance(network, get_result, extra_args)

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
			
			if to_network != null:
				crystal_ball.spawn_message()
				network_info[to_network]["order_processor"].intake_message(message, from_network)

func check_endpoint_allowance(network, get_result, extra_args):
	var local_token_contract = extra_args["local_token_contract"]
	var endpoint_contract = extra_args["endpoint_contract"]
	
	var allowance = get_result["result"]
	if allowance != "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff":
		var order_filler = network_info[network]["order_processor"].get_node("OrderFiller")
		print(network + " endpoint " + endpoint_contract + " needs approval to spend local token " + local_token_contract)
		order_filler.needs_to_approve = true
		order_filler.pending_approvals.append(
			{
				"endpoint_contract": endpoint_contract, 
				"local_token_contract": local_token_contract,
				"monitorable_token": extra_args["monitorable_token"]
			}
		)
		extra_args["monitorable_token"].get_node("MainPanel/Monitor").text = "Approving..."
	else:
		print(network + " endpoint " + endpoint_contract + " has allowance to spend local token " + local_token_contract)
		extra_args["monitorable_token"].approved = true

func ethereum_request_failed(network, method, extra_args):
	pass


func get_address():
	var file = File.new()
	file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
	var content = file.get_buffer(32)
	user_address = FastCcipBot.get_address(content)
	file.close()

func export_key():
	var file = File.new()
	file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
	var content = file.get_buffer(32)
	#Copy and paste this string into a wallet importer:
	print(content.hex_encode())

func get_gas_balances():
	for network in networks:
		perform_ethereum_request(network, "eth_getBalance", [user_address, "latest"])

func get_erc20_balance(network, token_contract):
	var chain_id = int(network_info[network]["chain_id"])
	var rpc = network_info[network]["rpc"]
	var file = File.new()
	file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.check_token_balance(content, chain_id, rpc, token_contract)
	perform_ethereum_request(network, "eth_call", [{"to": token_contract, "input": calldata}, "latest"], {"function_name": "check_token_balance", "token_contract": token_contract})

#DEBUG
var token_downshift = 0
func add_monitored_token(new_monitored_token):
	var serviced_network = new_monitored_token["serviced_network"]
	var local_token_contract = new_monitored_token["local_token_contract"]
	var endpoint_contract = new_monitored_token["endpoint_contract"]

	#well, it still doesn't filter quite right, but that will get sorted out
	if !new_monitored_token in monitorable_tokens:
		save_token(new_monitored_token)
		network_info[serviced_network]["monitored_tokens"].append(new_monitored_token)
		monitorable_tokens.append(new_monitored_token)
		
		var instanced_monitorable_token = monitorable_token.instance()
		instanced_monitorable_token.load_info(self, new_monitored_token)
		
		#position sorting needed
		$MonitoredTokenList/MonitoredTokenScroll/MonitoredTokenContainer.add_child(instanced_monitorable_token)
		instanced_monitorable_token.rect_position.y += token_downshift
		token_downshift += 270
		$MonitoredTokenList/MonitoredTokenScroll/MonitoredTokenContainer.rect_min_size.y += 270
		
		#check token approval
		var chain_id = int(network_info[serviced_network]["chain_id"])
		var rpc = network_info[serviced_network]["rpc"]
		var file = File.new()
		file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
		var content = file.get_buffer(32)
		file.close()
		var calldata = FastCcipBot.check_endpoint_allowance(content, chain_id, rpc, local_token_contract, endpoint_contract)
		perform_ethereum_request(serviced_network, "eth_call", [{"to": local_token_contract, "input": calldata}, "latest"], {"function_name": "check_endpoint_allowance", "local_token_contract": local_token_contract, "endpoint_contract": endpoint_contract, "monitorable_token": instanced_monitorable_token})


var transaction_downshift = 0
func load_transaction(transaction):
	var new_transaction = sent_transaction.instance()
	new_transaction.load_info(self, transaction)
	$SentTransactionsList/SentTransactionsScroll/SentTransactionsContainer.add_child(new_transaction)
	new_transaction.rect_position.y += transaction_downshift
	transaction_downshift += 101
	$SentTransactionsList/SentTransactionsScroll/SentTransactionsContainer.rect_min_size.y += 101
	return new_transaction

func save_token(token):
	var delete = File.new()
	delete.open("user://saved_tokens", File.WRITE)
	delete.close()
	
	var content
	var file = File.new()
	if file.file_exists("user://saved_tokens"):
		file.open("user://saved_tokens", File.READ)
		content = parse_json(file.get_as_text())
		file.close()
	
	var file2 = File.new()
	file.open("user://saved_tokens", File.WRITE)
	
	if content != null:
		if !token in content["tokens"]:
			content["tokens"].append(token)
	else:
		content = {"tokens": [token]}
	
	file.store_string(JSON.print(content))
	file.close()
	

func load_saved_tokens():
	var file = File.new()
	if file.file_exists("user://saved_tokens"):
		file.open("user://saved_tokens", File.READ)
		var content = parse_json(file.get_as_text())
		for token in content["tokens"]:
			add_monitored_token(token)
		file.close()
	

func update_balance(network, get_result):
	var balance = String(get_result["result"].hex_to_int())
	network_info[network]["gas_balance"] = balance
	$GasBalances.get_node(network).text = balance

func update_block_number(network, get_result):
	var latest_block = get_result["result"].hex_to_int()
	network_info[network]["latest_block"] = latest_block

