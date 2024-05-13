extends Control

var glow = preload("res://glow.tscn")

var header = "Content-Type: application/json"
var value = "1906588804305777"

var max_value: int = 20065888043057777
#var max_value: int = 20065888043057777

var network
var main_script
var user_address
var token_contract
var token_name
var token_decimals

var pending_orders = []
var order_filling_paused = false

var order_in_queue
var approval_in_queue
var current_tx_type

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

var gas_balance = "0"
var token_balance

var checked_for_approval = false
var approved = false
var active = false

var recipients = []
var target
var transaction_minimum_delay = 0

func initialize(main, _network, _token_contract):
	randomize()
	main_script = main
	user_address = Ethers.user_address
	network = _network
	token_contract = _token_contract
	get_parent().texture = load(Network.network_info[network]["logo"])
	get_erc20_name()
	get_network_gas_balance("update_gas_balance")

func _process(delta):
	transaction_minimum_delay -= delta
	if checking_for_tx_receipt:
		check_for_tx_receipt(delta)
	handle_approvals()
	prune_pending_orders(delta)
	if active && approved && !order_filling_paused && float(Ethers.convert_to_smallnum(gas_balance, 18)) > float(Network.network_info[network]["minimum_gas_threshold"]):
		if transaction_minimum_delay <= 0:
			order_filling_paused = true
			transaction_minimum_delay = 10
			create_order()
			fill_orders()

func create_order():
	var target_network = get_target_network()
	if target_network != "":
		var simulated_data = Crypto.new()
		var data = simulated_data.generate_random_bytes(32).hex_encode()
		var target = get_target(target_network)
		var order = {
				"chain_selector": Network.network_info[target_network]["chain_selector"],
				"endpoint_contract": Network.network_info[target_network]["endpoint_contract"],
				"recipient": Ethers.user_address,
				"data": data,
				"amount": "1000",
				"token_contract": token_contract,
				"target": target
			}
		intake_order(order)

func get_target_network():
	if network in recipients:
		recipients.erase(network)
	if !recipients.empty():
		return recipients[randi()%recipients.size()]
	return ""

func get_target(network):
	for target in main_script.targets:
		if target["network"] == network:
			return target["rect_position"]

func intake_order(order):
	var is_new_order = true
	if !pending_orders.empty():
		for pending_order in pending_orders:
			if pending_order["data"] == order["data"]:
				is_new_order = false
	if is_new_order:
		order["checked"] = false
		order["time_to_prune"] = 300
		pending_orders.append(order)

func fill_orders():
	if !pending_orders.empty() && !needs_to_approve && approved:
		for pending_order in pending_orders:
			if pending_order["checked"] == false:
				order_in_queue = pending_order
				get_network_gas_balance("initiate_transaction_sequence")
			

func handle_approvals():
	if needs_to_approve && !order_filling_paused:
		if !pending_approvals.empty():
			order_filling_paused = true
			approval_in_queue = pending_approvals[0]
			pending_approvals.pop_front()
			get_network_gas_balance("initiate_transaction_sequence")
		else:
			needs_to_approve = false
			order_filling_paused = false

func initiate_transaction_sequence(callback):
	if callback["success"]:
		var balance = String(callback["result"].hex_to_int())
		var network_info = Network.network_info.duplicate()
		if float(balance) > float(network_info[network]["minimum_gas_threshold"]):
			if current_tx_type == "order":
				
				var key = Ethers.get_key()
				
				var chain_id = Network.network_info[network]["chain_id"]
				var rpc = Network.network_info[network]["rpc"]
				var entrypoint_contract = Network.network_info[network]["entrypoint_contract"]
				
				var chain_selector = order_in_queue["chain_selector"]
				var endpoint_contract = order_in_queue["endpoint_contract"]
				var recipient = order_in_queue["recipient"]
				var data = order_in_queue["data"]
				var amount = order_in_queue["amount"]
				var token_contract = order_in_queue["token_contract"]
				var calldata = FastCcipBot.get_fee_value(key, chain_id, entrypoint_contract, rpc, gas_price, tx_count, chain_selector, endpoint_contract, recipient, data, token_contract, amount)
				
				Ethers.perform_request(
				"eth_call", 
				[{"to": entrypoint_contract, "input": calldata}, "latest"], 
				Network.network_info[network]["rpc"], 
				0, 
				self, 
				"get_fee_value", 
				{"function_name": "get_fee_value", "token_contract": token_contract}
				)
				
			else:
				
				Ethers.perform_request(
				"eth_getTransactionCount", 
				[user_address, "latest"], 
				Network.network_info[network]["rpc"], 
				0, 
				self, 
				"get_tx_count", 
				{}
				)
				
		else:
			gas_error("failed to initiate transaction")
	else:
		rpc_error("failed to initiate transaction")

func get_fee_value(callback):
	if callback["success"]:
		value = FastCcipBot.decode_u256(callback["result"])
		print(value + " ? " + String(max_value))
		if int(value) < max_value:
			
			Ethers.perform_request(
				"eth_getTransactionCount", 
				[user_address, "latest"], 
				Network.network_info[network]["rpc"], 
				0, 
				self, 
				"get_tx_count", 
				{}
				)
		else:
			gas_error("ccip fee too high")
	else:
		rpc_error("failed to get ccip fee")

func get_tx_count(callback):
	if callback["success"]:
		tx_count = callback["result"].hex_to_int()
		
		Ethers.perform_request(
				"eth_gasPrice", 
				[], 
				Network.network_info[network]["rpc"], 
				0, 
				self, 
				"get_gas_price", 
				{}
				)
		
	else:
		rpc_error("failed to get transaction count")

func get_gas_price(callback):
	if callback["success"]:
		gas_price = int(ceil((callback["result"].hex_to_int() * 1.1))) #adjusted up
	
		
		var network_info = Network.network_info.duplicate()
		var rpc = network_info[network]["rpc"]
		var chain_id = int(network_info[network]["chain_id"])
		var entrypoint_contract = Network.network_info[network]["entrypoint_contract"]
		
		mark_queued_order_as_checked()
		
		var maximum_gas_fee = network_info[network]["maximum_gas_fee"]
		
		#it would be good to perform a gas estimate instead of relying on a minimum gas threshold
		if maximum_gas_fee != "":
			if gas_price > int(maximum_gas_fee):
				gas_fee_too_high()
				return
		
		var key = Ethers.get_key()
		var calldata
		
		if !needs_to_approve:
			
			var new_glow = glow.instance()
			new_glow.target = order_in_queue["target"]
			get_parent().add_child(new_glow)
			
			current_tx_type = "order"
			
			var chain_selector = order_in_queue["chain_selector"]
			var endpoint_contract = order_in_queue["endpoint_contract"]
			var recipient = order_in_queue["recipient"]
			var data = order_in_queue["data"]
			var amount = order_in_queue["amount"]
			var token_contract = order_in_queue["token_contract"]
	
			calldata = "0x" + FastCcipBot.test_send(
				key, 
				chain_id, 
				entrypoint_contract, 
				rpc, 
				gas_price,
				tx_count, 
				chain_selector, 
				endpoint_contract, 
				recipient, 
				data, 
				token_contract, 
				amount, 
				value
				)
	
		else:
			current_tx_type = "approval"
			calldata = "0x" + FastCcipBot.approve_endpoint_allowance(
				key, 
				chain_id, 
				entrypoint_contract, 
				rpc, 
				gas_price, 
				tx_count, 
				token_contract
				)
				
		
		Ethers.perform_request(
				"eth_sendRawTransaction", 
				[calldata], 
				rpc, 
				0, 
				self, 
				"get_transaction_hash", 
				{}
				)
		
	else:
		rpc_error("failed to get gas price")

func get_transaction_hash(callback):
	if callback["success"]:
			tx_hash = callback["result"]
			checking_for_tx_receipt = true
			tx_receipt_poll_timer = 4
	else:
		rpc_error("failed to get transaction hash")

func check_for_tx_receipt(delta):
	tx_receipt_poll_timer -= delta
	if tx_receipt_poll_timer < 0:
		tx_receipt_poll_timer = 4
		var network_info = Network.network_info.duplicate()
		var rpc = network_info[network]["rpc"]
		Ethers.perform_request(
			"eth_getTransactionReceipt", 
			[tx_hash], 
			rpc, 
			0, 
			self, 
			"check_transaction_receipt",
			{}
			)

func check_transaction_receipt(callback):
	tx_receipt_poll_timer = 4
	if callback["success"]:
		#also tx gas bumping
		if callback["result"] != null:
			var success = callback["result"]["status"]
			if success == "0x1":
				print("order filled")
				checking_for_tx_receipt = false	
				order_filling_paused = false
				var block_number = callback["result"]["blockNumber"]
				if current_tx_type == "approval":
					approved = true
					get_parent().get_node("Approving").visible = false
			else:
				print("failed to fill order")
				checking_for_tx_receipt = false	
				order_filling_paused = false
	else:
		checking_for_tx_receipt = false	
		rpc_error("failed to check for transaction receipt")
			

func get_network_gas_balance(callback_function): 
	Ethers.perform_request(
				"eth_getBalance", 
				[user_address, "latest"], 
				Network.network_info[network]["rpc"], 
				0, 
				self, 
				callback_function, 
				{}
				)


func update_gas_balance(callback):
	if callback["success"]:
		gas_balance = String(callback["result"].hex_to_int())
	else:
		gas_balance = "0"
	get_erc20_decimals()


func get_erc20_name():
	var network_info = Network.network_info.duplicate()
	var chain_id = int(network_info[network]["chain_id"])
	var rpc = network_info[network]["rpc"]
	var key = Ethers.get_key()
	var calldata = FastCcipBot.get_token_name(key, chain_id, rpc, token_contract)
	
	Ethers.perform_request(
				"eth_call", 
				[{"to": token_contract, "input": calldata}, "latest"], 
				rpc, 
				0, 
				self, 
				"update_info", 
				{"function_name": "get_token_name", "token_contract": token_contract}
				)


func get_erc20_decimals():
	var network_info = Network.network_info.duplicate()
	var chain_id = int(network_info[network]["chain_id"])
	var rpc = network_info[network]["rpc"]
	var key = Ethers.get_key()
	var calldata = FastCcipBot.get_token_decimals(key, chain_id, rpc, token_contract)
	
	Ethers.perform_request(
				"eth_call", 
				[{"to": token_contract, "input": calldata}, "latest"], 
				network_info[network]["rpc"], 
				0, 
				self,
				"update_info", 
				{"network": network, "function_name": "get_token_decimals", "token_contract": token_contract}
				)


func get_erc20_balance():
	var chain_id = int(Network.network_info[network]["chain_id"])
	var rpc = Network.network_info[network]["rpc"]
	var key = Ethers.get_key()
	var calldata = FastCcipBot.check_token_balance(key, chain_id, rpc, token_contract)

	Ethers.perform_request(
				"eth_call", 
				[{"to": token_contract, "input": calldata}, "latest"], 
				rpc, 
				0, 
				self, 
				"update_info", 
				{"function_name": "check_token_balance", "token_contract": token_contract}
				)


func check_for_entrypoint_allowance():
	if int(gas_balance) > 0 && !checked_for_approval:
		var network_info = Network.network_info
		var entrypoint_contract = network_info[network]["entrypoint_contract"]
		checked_for_approval == true
		var chain_id = int(network_info[network]["chain_id"])
		var rpc = network_info[network]["rpc"]
		var key = Ethers.get_key()
		var calldata = FastCcipBot.check_endpoint_allowance(key, chain_id, rpc, token_contract, entrypoint_contract)
	
		Ethers.perform_request(
				"eth_call", 
				[{"to": token_contract, "input": calldata}, "latest"], 
				rpc, 
				0, 
				self, 
				"update_info", 
				{"function_name": "check_entrypoint_allowance", "token_contract": token_contract, "entrypoint_contract": entrypoint_contract}
				)


func update_info(callback):
	if callback["success"]:
		var args = callback["callback_args"]
		if args["function_name"] == "get_token_name":
			if callback["result"] != "0x":
				token_name = FastCcipBot.decode_hex_string(callback["result"])
		
		if args["function_name"] == "get_token_decimals":
			if callback["result"] != "0x":
				token_decimals = FastCcipBot.decode_u8(callback["result"])
				get_erc20_balance()
			
		if args["function_name"] == "check_token_balance":
			if callback["result"] != "0x":
				token_balance = Ethers.convert_to_smallnum(FastCcipBot.decode_u256(callback["result"]), 18)
				var gas = Ethers.convert_to_smallnum(gas_balance, token_decimals)
				get_parent().get_node("Balances").text = "Gas: " + gas + "\n" + token_name + ": " + token_balance
		
		if args["function_name"] == "check_entrypoint_allowance":
			var allowance = callback["result"]
			if allowance != "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff":
				needs_to_approve = true
				pending_approvals.append("")
				get_parent().get_node("Approving").visible = true
			else:
				approved = true
			

func rpc_error(error):
	order_filling_paused = false
	print("rpc error: " + error)

func gas_error(error):
	order_filling_paused = false
	print("insufficient gas:" + error)

func gas_fee_too_high():
	order_filling_paused = false
	print("gas fee too high")
	
func invalid_order():
	mark_queued_order_as_checked()
	order_filling_paused = false
	print("invalid order")

func mark_queued_order_as_checked():
	for pending_order in pending_orders:
		if pending_order["data"] == order_in_queue["data"]:
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
