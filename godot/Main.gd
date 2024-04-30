extends Control


#Giant mess before refactor

var user_address
var user_balance = "0"

var my_header = "Content-Type: application/json"


#"base_id" will need to be replaced with a generalized label

var networks = ["Ethereum Sepolia"]

var network_info = {
	"Ethereum Sepolia": 
		{
		"chain_id": 11155111, 
		"rpc": "https://endpoints.omniatech.io/v1/eth/sepolia/public", 
		"onramp_contract": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e", 
		"bnm_token_contract": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
		"endpoint_contract": "", 
		"pending_order_queue": [],
		"tx_count": 0,
		"gas_price": 0,
		"tx_function_name": ""
		
		},
	"Arbitrum Sepolia": {},
	"Optimism Sepolia": {},
	"Polygon Mumbai": {},
	"Base Testnet": {}
}


#Sepolia Testnet
var base_id = 11155111
var my_rpc = "https://endpoints.omniatech.io/v1/eth/sepolia/public"

#BnM
var token_address = "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05"
#OnRamp
# The bot must watch the onRamp for SentMessageRequested events
var onramp_address = "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e"

var endpoint_address = "0x39E98Ab623cf367462d049aB389E6f3083556dA8"



var signed_data = ""

var tx_count 
var gas_price
var confirmation_timer = 0
var tx_function_name = ""

var latest_block = 1
var pending_order

var transfer_amount = 0
var recipient


#ETHEREUM SEPOLIA
#chain id
#default rpc
#onramp_address
#default endpoint_address
#pending_order queue
#ARBITRUM SEPOLIA
#OPTIMISM SEPOLIA
#POLYGON MUMBAI
#BASE TESTNET




#Need: import and export keys; add and remove networks, add and remove endpoint,
# add and remove token contracts; ability to monitor multiple networks and tokens
# without conflicts.  An event queue to filter redundant events and a
# transaction queue to bank pending tx as they come in


func _ready():
	check_keystore()
	get_address()
	get_balance()
	get_block_number()


var log_timer = 1
func _process(delta):
	log_timer -= delta
	if log_timer < 0:
		log_timer = 1
		#fetches the block number, then the logs for the last 2 blocks
		if http_request_delete_block_number == null:
			get_block_number()
		else:
			http_request_delete_block_number.queue_free()
			http_request_delete_block_number = null
	

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





var http_request_delete_balance
var http_request_delete_block_number
var http_request_delete_logs
var http_request_delete_filter
var http_request_delete_tx_info
var http_request_delete_tx_read
var http_request_delete_tx_write
var http_request_delete_gas
var http_request_delete_count

func get_balance():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_balance = http_request
	http_request.connect("request_completed", self, "get_balance_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_getBalance", "params": [user_address, "latest"], "id": 7}
	
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_balance_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		var balance = String(get_result["result"].hex_to_int())
		user_balance = balance
		$Balance.text = balance

	http_request_delete_balance.queue_free()


func get_block_number():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_block_number = http_request
	http_request.connect("request_completed", self, "get_block_number_attempted")
	
	var tx = {"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 7}
	
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func get_block_number_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		latest_block = get_result["result"].hex_to_int()
		get_logs()
	
	http_request_delete_block_number.queue_free()
	http_request_delete_block_number = null
		

func get_logs():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_logs = http_request
	http_request.connect("request_completed", self, "get_logs_attempted")
	
	#for some reason AVAX needs to specify latest only
	var tx = {"jsonrpc": "2.0", "method": "eth_getLogs", "params": [{"fromBlock": "latest", "address": onramp_address, "topics": ["0xd0c3c799bf9e2639de44391e7f524d229b2b55f5b1ea94b2bf7da42f7243dddd"]}], "id": 7}
	#var tx = {"jsonrpc": "2.0", "method": "eth_getLogs", "params": [{"fromBlock": "0x" + String(latest_block - 1), "toBlock": "0x" + String(latest_block),"address": "0x198EF79F1F515F02dFE9e3115eD9fC07183f02fC"}], "id": 7}
	
	var error = http_request.request(my_rpc, 
	[my_header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func get_logs_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		#instead of ["result"][0] it will need to iterate through the array 
		#and queue events
		if get_result["result"] != []:
			if pending_order != get_result["result"][0]["data"].right(2):
				pending_order = get_result["result"][0]["data"].right(2)
				print("filtering")
				filter_order()
#				print(pending_order)
#				try_fill_order()
				
			
#			pending_tx_hash = get_result["result"][0]["transactionHash"]
#			print(pending_tx_hash)
#			get_tx_info()
	
	http_request_delete_logs.queue_free()
	http_request_delete_logs = null
#

func filter_order():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_filter = http_request
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
	
	http_request_delete_filter.queue_free()
	http_request_delete_filter = null


func try_fill_order():
	tx_function_name = "fill_order"
	get_tx_count()


func get_tx_count():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_count = http_request
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
	http_request_delete_count.queue_free()
	estimate_gas()


func estimate_gas():
	var http_request = HTTPRequest.new()
	$HTTP.add_child(http_request)
	http_request_delete_gas = http_request
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
	http_request_delete_gas.queue_free()
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
	http_request_delete_tx_write = http_request
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
		get_balance()
	else:
		pass
	
	http_request_delete_tx_write.queue_free()


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
