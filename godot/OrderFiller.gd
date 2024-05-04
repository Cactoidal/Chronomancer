extends HTTPRequest

var header = "Content-Type: application/json"

var network
var main_script
var network_info
var user_address

var pending_orders = []
var order_filling_paused = false

var order_in_queue
var approval_in_queue
var current_tx_type
var current_method
var tx_count
var gas_price
var tx_function_name
var tx_hash

var pending_approval
var pending_tx

var checking_for_tx_receipt = false
var tx_receipt_poll_timer = 4

var pending_approvals = []
var needs_to_approve = false


#need error catching for faulty 200 responde codes with no return value
#double check how the tx hash and tx receipt are structured

func _ready():
	network = get_parent().network
	main_script = get_parent().main_script
	network_info = get_parent().network_info
	user_address = get_parent().user_address
	self.connect("request_completed", self, "resolve_ethereum_request")



func _process(delta):
	if checking_for_tx_receipt:
		check_for_tx_receipt(delta)
	handle_approvals()
	fill_orders()
	prune_pending_orders(delta)

func intake_order(order):
	var is_new_order = true
	if !pending_orders.empty():
		for pending_order in pending_orders:
			if pending_order["message"] == order["message"]:
				is_new_order = false
	if is_new_order:
		order["checked"] = false
		order["time_to_prune"] = 300
		pending_orders.append(order)

func fill_orders():
	if !pending_orders.empty() && !needs_to_approve:
		for pending_order in pending_orders:
			if pending_order["checked"] == false && !order_filling_paused:
				order_filling_paused = true
				order_in_queue = pending_order
				current_method = "eth_getBalance"
				perform_ethereum_request("eth_getBalance", [user_address, "latest"])

func handle_approvals():
	if needs_to_approve && !order_filling_paused:
		if !pending_approvals.empty():
			order_filling_paused = true
			current_method = "eth_getBalance"
			approval_in_queue = pending_approvals[0].duplicate()
			pending_approvals.pop_front()
			perform_ethereum_request("eth_getBalance", [user_address, "latest"])
		else:
			needs_to_approve = false
			order_filling_paused = false

func perform_ethereum_request(method, params, extra_args={}):
	var rpc = network_info["rpc"]
	
	var tx = {"jsonrpc": "2.0", "method": method, "params": params, "id": 7}
	
	request(rpc, 
	[header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func resolve_ethereum_request(result, response_code, headers, body):
	var get_result = parse_json(body.get_string_from_ascii())
	match current_method:
		"eth_getBalance": check_gas_balance(get_result, response_code)
		"eth_call": check_order_validity(get_result, response_code)
		"eth_getTransactionCount": get_tx_count(get_result, response_code)
		"eth_gasPrice": get_gas_price(get_result, response_code)
		"eth_sendRawTransaction": get_transaction_hash(get_result, response_code)
		"eth_getTransactionReceipt": check_transaction_receipt(get_result, response_code)

func check_gas_balance(get_result, response_code):
	if response_code == 200:
		var balance = String(get_result["result"].hex_to_int())
		#may need to be checked in rust
		if int(balance) > int(network_info["minimum_gas_threshold"]):
			current_method = "eth_call"
			if !needs_to_approve:
				print("composing order")
				compose_message(order_in_queue["message"], order_in_queue["from_network"])
			else:
				current_method = "eth_getTransactionCount"
				perform_ethereum_request("eth_getTransactionCount", [user_address, "latest"])
		else:
			gas_error()
	else:
		rpc_error()


func compose_message(message, from_network):
	
	var rpc = network_info["rpc"]
	var chain_id = network_info["chain_id"]
	var endpoint_contract = network_info["endpoint_contract"]
	var monitored_tokens = network_info["monitored_tokens"]
	
	var local_token_contracts: PoolStringArray
	var remote_token_contracts: PoolStringArray
	var token_minimum_list: PoolStringArray
	
	for token in monitored_tokens:
		local_token_contracts.append(token["local_token_contract"])
		remote_token_contracts.append(token["monitored_networks"][from_network])
		#allow custom minimum
		token_minimum_list.append("0")
		
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	
	var calldata = FastCcipBot.filter_order(content, chain_id, endpoint_contract, rpc, message, local_token_contracts, remote_token_contracts, token_minimum_list)
	
	perform_ethereum_request("eth_call", [{"to": endpoint_contract, "input": calldata}, "latest"])


func check_order_validity(get_result, response_code):
	if response_code == 200:
		#var valid = FastCcipBot.decode_bool(get_result["result"])
		var valid = get_result["result"]
		if valid != "0x0000000000000000000000000000000000000000000000000000000000000000":
			current_method = "eth_getTransactionCount"
			perform_ethereum_request("eth_getTransactionCount", [user_address, "latest"])
		else:
			invalid_order()
	else:
		rpc_error()

func get_tx_count(get_result, response_code):
	if response_code == 200:
		tx_count = get_result["result"].hex_to_int()
		current_method = "eth_gasPrice"
		perform_ethereum_request("eth_gasPrice", [])
	else:
		rpc_error()

func get_gas_price(get_result, response_code):
	if response_code == 200:
		gas_price = int(ceil((get_result["result"].hex_to_int() * 1.1))) #adjusted up
		#adjustable filter for gas spikes
		current_method = "eth_sendRawTransaction"
		
		var rpc = network_info["rpc"]
		var chain_id = network_info["chain_id"]
		var endpoint_contract = network_info["endpoint_contract"]
		
		mark_queued_order_as_checked()
		
		var file = File.new()
		file.open("user://keystore", File.READ)
		var content = file.get_buffer(32)
		file.close()
		if !needs_to_approve:
			current_tx_type = "order"
			var local_token = FastCcipBot.decode_address(order_in_queue["local_token"])
			FastCcipBot.fill_order(content, chain_id, endpoint_contract, rpc, gas_price, tx_count, order_in_queue["message"], local_token, self)
		else:
			current_tx_type = "approval"
			var local_token_contract = approval_in_queue["local_token_contract"]
			print("approving endpoint " + endpoint_contract + " allowance to spend local token " + local_token_contract)
			FastCcipBot.approve_endpoint_allowance(content, chain_id, endpoint_contract, rpc, gas_price, tx_count, local_token_contract, self)
	else:
		rpc_error()

func set_signed_data(var signature):
	var signed_data = "".join(["0x", signature])
	perform_ethereum_request("eth_sendRawTransaction", [signed_data])

func get_transaction_hash(get_result, response_code):
	if response_code == 200 && get_result.has("result"):
		print("sent tx")
		print(get_result)
		tx_hash = get_result["result"]
		checking_for_tx_receipt = true
		current_method = "eth_getTransactionReceipt"
		tx_receipt_poll_timer = 4
		
		var transaction = {
		"network": network,
		"type": current_tx_type,
		"hash": tx_hash
		}
		
		pending_tx = main_script.load_transaction(transaction)
		
		
	else:
		rpc_error()

func check_for_tx_receipt(delta):
	tx_receipt_poll_timer -= delta
	if tx_receipt_poll_timer < 0:
		tx_receipt_poll_timer = 4
		perform_ethereum_request("eth_getTransactionReceipt", [tx_hash])

func check_transaction_receipt(get_result, response_code):
	tx_receipt_poll_timer = 4
	if response_code == 200:
		#also tx gas bumping
		#print(get_result)
		if get_result.has("result"): 
			if get_result["result"] != null:
				var success = get_result["result"]["status"]
				if success == "0x1":
					print("order filled")
					checking_for_tx_receipt = false	
					order_filling_paused = false
					var block_number = get_result["result"]["blockNumber"]
					pending_tx.was_successful(true, network, block_number)
					if current_tx_type == "approval":
						approval_in_queue["monitorable_token"].get_node("MainPanel/Monitor").text = "Start Monitoring"
						approval_in_queue["monitorable_token"].approved = true
				else:
					print("failed to fill order")
					checking_for_tx_receipt = false	
					order_filling_paused = false
					pending_tx.was_successful(false, network)
	else:
		checking_for_tx_receipt = false	
		rpc_error()
			

func rpc_error():
	order_filling_paused = false
	print("rpc error")

func gas_error():
	order_filling_paused = false
	print("insufficient gas")

func invalid_order():
	mark_queued_order_as_checked()
	order_filling_paused = false
	print("invalid order")

func mark_queued_order_as_checked():
	for pending_order in pending_orders:
		if pending_order["message"] == order_in_queue["message"]:
			pending_order["checked"] = true
	
func prune_pending_orders(delta):
	if !pending_orders.empty():
		var deletion_queue = []
		for pending_order in pending_orders:
			pending_order["time_to_prune"] -= delta
			if pending_order["time_to_prune"] < 0:
				deletion_queue.append(pending_order)
		if !deletion_queue.empty():
			for deletable in deletion_queue:
				print("old order timed out")
				pending_orders.erase(deletable)
				
