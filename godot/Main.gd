extends Control

# Refactoring. Still a giant mess, but improving.  eth_methods are now processed through a generalized function and
# order filtering and filling are being offloaded to per-chain HTTP Request nodes

var eth_http_request = preload("res://EthRequest.tscn")
var order_processor = preload("res://OrderProcessor.tscn")

var order_filter_http_request = preload("res://OrderFilterRequest.tscn")

var user_address
var header = "Content-Type: application/json"

var networks = ["Ethereum Sepolia"]

var fuji_selector = "ccf0a31a221f3c9b"
var mumbai_selector = "adecc60412ce25a5"
var sepolia_selector = "de41ba4fc9d91ad9"
var optimism_selector = "24f9b897ef58a922"
var arbitrum_selector = "54abf9fb1afeaf95"

var network_info = {
	"Ethereum Sepolia": 
		{
		"chain_id": 11155111,
		"chain_selector": "de41ba4fc9d91ad9", 
		"rpc": "https://endpoints.omniatech.io/v1/eth/sepolia/public",
		"gas_balance": "0", 
		"onramp_contract": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e", 
		"default_endpoint_contract": "0x39E98Ab623cf367462d049aB389E6f3083556dA8",
		"monitored_tokens": [{"token_contract": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05", "token_balance": "0", "endpoint_contract": "", "minimum": 0.00000001}], #BnM address
		"pending_message_queue": [],
		"pause_order_checking": false, 
		"pending_order_queue": [],
		"pause_order_filling": false,
		"completed_order_queue": [],
		"minimum_gas_threshold": 0,
		"latest_block": 0,
		"tx_count": 0,
		"gas_price": 0,
		"tx_function_name": "",
		"order_processor": null
		},
	"Arbitrum Sepolia": {},
	"Optimism Sepolia": {},
	"Polygon Mumbai": {},
	"Base Testnet": {}
}

var signed_data = ""

#Need: import and export keys; add and remove networks, add and remove endpoint,
# add and remove token contracts; ability to monitor multiple networks and tokens
# without conflicts.  An event queue to filter redundant events and a
# transaction queue to bank pending tx as they come in

func _ready():
	check_keystore()
	get_address()
	get_gas_balances()
	for network in networks:
		var new_processor = order_processor.instance()
		network_info[network]["order_processor"] = new_processor
		new_processor.network_info = network_info[network].duplicate()
		$HTTP.add_child(new_processor)


var log_timer = 1

func _process(delta):
	#this whole system will be much cleaner when each chain has its own
	#dedicated http request for processing orders.  no more need for queue arrays
	check_for_orders(delta)
	#add autoprune
	fill_orders()
	log_timer -= delta
	if log_timer < 0:
		log_timer = 1
		get_logs()

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

func get_logs():
	for network in networks:
		perform_ethereum_request(network, "eth_getLogs", [{"fromBlock": "latest", "address": network_info[network]["onramp_contract"], "topics": ["0xd0c3c799bf9e2639de44391e7f524d229b2b55f5b1ea94b2bf7da42f7243dddd"]}])

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
		"eth_call": handle_eth_call(network, get_result, extra_args)
		"eth_getTransactionCount": pass
		"eth_gasPrice": pass
		"eth_sendRawTransaction": pass
		"eth_getTransactionHash": pass

func update_balance(network, get_result):
	var balance = String(get_result["result"].hex_to_int())
	network_info[network]["gas_balance"] = balance

func update_block_number(network, get_result):
	var latest_block = get_result["result"].hex_to_int()
	network_info[network]["latest_block"] = latest_block

func check_for_ccip_messages(network, get_result):
	if get_result["result"] != []:
		for message in get_result["result"]:
			network_info[network]["order_processor"].intake_message(message)
			
	
func check_for_orders(delta):
	for network in networks:
		if network_info[network]["pending_message_queue"] != []:
			if !network_info[network]["pause_order_checking"]:
				network_info[network]["pause_order_checking"] = true
				
				var temp_network_info = network_info[network].duplicate()
				
				var message = temp_network_info[network]["pending_message_queue"][0]
				
				var potential_order = {
					"network": network,
					"message": message,
					"filtering_paused": false,
					"time_until_prune": 300
				}
				
				var http_request = order_filter_http_request.instance()
				http_request.potential_order = potential_order
				$HTTP.add_child(http_request)
				
			for order in network_info[network]["pending_message_queue"]:
				order["time_until_prune"] -= delta
				if order["time_until_prune"] < 0:
					network_info[network]["pending_message_queue"].erase(order)

func filter_orders():
	if order_filter_queue != []:
		for potential_order in order_filter_queue:
			if !potential_order["filtering_paused"]:
				potential_order["filtering_paused"] = true
				
				check_order_validity(potential_order, "order_filter_queue")
				
				potential_order["monitored_tokens"].erase(potential_order["monitored_tokens"][0])
				if potential_order["monitored_tokens"] == []:
					network_info[potential_order["network"]].pause_order_checking = false
					order_filter_queue.erase(potential_order)

func check_order_validity(potential_order, current_queue):
	var network = potential_order["network"]
	var message = potential_order["message"]
	var rpc = network_info[network]["rpc"]
	var chain_id = network_info[network]["chain_id"]
	var destination_selector = network_info[network]["chain_selector"]
	var token_contract = network_info[network]["monitored_tokens"][0]["token_contract"]
	var endpoint_contract = network_info[network]["monitored_tokens"][0]["endpoint_contract"]
				
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.filter_order(content, chain_id, endpoint_contract, rpc, message, token_contract)
	perform_ethereum_request(network, "eth_call", [{"to": endpoint_contract, "input": calldata}, "latest"], {"function_name": "filter_order", "potential_order": potential_order, "current_queue": current_queue})


func handle_eth_call(network, get_result, extra_args):
	
	if extra_args["function_name"] == "filter_order":
		var order = extra_args["potential_order"]
		var valid = FastCcipBot.decode_bool(get_result)
		
		if extra_args["current_queue"] == "order_filter_queue":
			if valid:
				network_info[network]["pending_order_queue"].append(order)
			else:
				if order in order_filter_queue:
					var index = order_filter_queue.find(order)
					order_filter_queue[index]["filtering_paused"] = false
		
		elif extra_args["current_queue"] == "pending_order_queue":
			if valid:
				pass
			else:
				network_info[network]["pending_order_queue"].erase(network_info[network]["pending_order_queue"][0])
				network_info[network]["pause_order_filling"] = false
				

func fill_orders():
	for network in networks:
		if network_info[network]["pending_order_queue"] != [] && !network_info[network]["pause_order_filling"]:
			network_info[network]["pause_order_filling"] = true
			check_order_validity(network_info[network]["pending_order_queue"][0], "pending_order_queue")
	#check if the order is still valid, i.e. you still have enough balance to fill it

func ethereum_request_failed(network, method, extra_args):
	pass



	

func old_filter_order():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_deletion_queue.append([http_request, 5])
	http_request.connect("request_completed", self, "filter_order_attempted")
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.filter_order(content, base_id, endpoint_address, my_rpc, pending_order,token_address)
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"to": endpoint_address, "input": calldata}, "latest"], "id": 7}
	
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func filter_order_attempted(result, response_code, headers, body):
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		print(get_result)
	


func try_fill_order():
	tx_function_name = "fill_order"
	get_tx_count()


func get_tx_count():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_deletion_queue.append([http_request, 5])
	http_request.connect("request_completed", self, "get_tx_count_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_getTransactionCount", "params": [user_address, "latest"], "id": 7}
	
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_tx_count_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		var count = get_result["result"].hex_to_int()
		tx_count = count
	else:
		pass

	estimate_gas()


func estimate_gas():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_deletion_queue.append([http_request, 5])
	http_request.connect("request_completed", self, "estimate_gas_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_gasPrice", "params": [], "id": 7}
	
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func estimate_gas_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		var estimate = get_result["result"].hex_to_int()
		gas_price = int(float(estimate) * 1.12)
	else:
		pass

	call(tx_function_name)

func fill_order():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	FastCcipBot.fill_order(content, base_id, endpoint_address, my_rpc, gas_price, tx_count, pending_order, self)

func set_signed_data(var signature):
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_deletion_queue.append([http_request, 5])
	http_request.connect("request_completed", self, "attempted_tx")
	
	var signed_data = "".join(["0x", signature])
	
	var tx = {"jsonrpc": "2.0", "method": "eth_sendRawTransaction", "params": [signed_data], "id": 7}
	print(signed_data)
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))


func attempted_tx(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	print(get_result)

	if response_code == 200:
		#get tx hash here
		get_balance()
	else:
		pass
	



#tx will return receipt, switch this to eth_getTransactionHash to check status of tx

#func get_tx_info():
#	var http_request = HTTPRequest.new()
#	$HTTP.add_child(http_request)
#	http_request_delete_tx_info = http_request
#	http_request.connect("request_completed", self, "get_tx_info_attempted")
#
#	#for some reason AVAX needs to specify latest only
#	var tx = {"jsonrpc": "2.0", "method": "eth_getTransactionByHash", "params": [pending_tx_hash], "id": 7}
#	#var tx = {"jsonrpc": "2.0", "method": "eth_getLogs", "params": [{"fromBlock": "0x" + String(latest_block - 1), "toBlock": "0x" + String(latest_block),"address": "0x198EF79F1F515F02dFE9e3115eD9fC07183f02fC"}], "id": 7}
#
#	var error = http_request.request(my_rpc, 
#	[my_header], 
#	true, 
#	HTTPClient.METHOD_POST, 
#	JSON.print(tx))
#
#func get_tx_info_attempted(result, response_code, headers, body):
#
#	var get_result = parse_json(body.get_string_from_ascii())
#
#	if response_code == 200:
#		print(get_result)
#
#	http_request_delete_tx_info.queue_free()
#	http_request_delete_tx_info = null
