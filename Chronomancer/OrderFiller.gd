extends Control

var network
var main_script
var user_address

var pending_orders = []
var order_filling_paused = false

var order_in_queue
var approval_in_queue
var current_tx_type
var tx_count
var gas_price

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
	user_address = Ethers.user_address


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
				var network_info = Network.network_info.duplicate()
				var rpc = network_info[network]["rpc"]
				Ethers.perform_request(
					"eth_getBalance", 
					[user_address, "latest"], 
					rpc, 
					0, 
					self, 
					"update_gas_balance", 
					{}
					)

func handle_approvals():
	if needs_to_approve && !order_filling_paused:
		if !pending_approvals.empty():
			order_filling_paused = true
			approval_in_queue = pending_approvals[0].duplicate()
			pending_approvals.pop_front()
			var network_info = Network.network_info.duplicate()
			var rpc = network_info[network]["rpc"]
			Ethers.perform_request(
				"eth_getBalance", 
				[user_address, "latest"], 
				rpc, 
				0, 
				self, 
				"update_gas_balance", 
				{}
				)
		else:
			needs_to_approve = false
			order_filling_paused = false


func update_gas_balance(callback):
	if callback["success"]:
		var balance = String(callback["result"].hex_to_int())
		balance = Ethers.convert_to_smallnum(balance, 18)
		
		var network_info = Network.network_info.duplicate()
		
		if float(balance) > float(network_info[network]["minimum_gas_threshold"]):
	
			if !needs_to_approve:
				compose_message(order_in_queue["message"], order_in_queue["from_network"])
			else:
				var rpc = network_info[network]["rpc"]
				Ethers.perform_request(
					"eth_getTransactionCount", 
					[user_address, "latest"], 
					rpc, 
					0, 
					self, 
					"get_tx_count", 
					{}
					)
		else:
			gas_error("failed to update gas balance")
	else:
		rpc_error("failed to update gas balance")


func compose_message(message, from_network):
	var network_info = Network.network_info.duplicate()
	var rpc = network_info[network]["rpc"]
	var chain_id = int(network_info[network]["chain_id"])
	var endpoint_contract = network_info[network]["endpoint_contract"]
	var monitored_tokens = network_info[network]["monitored_tokens"]
	
	var local_token_contracts: PoolStringArray
	var remote_token_contracts: PoolStringArray
	var token_minimum_list: PoolStringArray
	
	for token in monitored_tokens:
		local_token_contracts.append(token["local_token_contract"])
		remote_token_contracts.append(token["monitored_networks"][from_network])
		token_minimum_list.append(token["minimum"])
	
		
	var key = Ethers.get_key()
	
	var calldata = FastCcipBot.filter_order(
		key, 
		chain_id, 
		endpoint_contract, 
		rpc, message, 
		local_token_contracts, 
		remote_token_contracts, 
		token_minimum_list
		)
		
	Ethers.perform_request(
		"eth_call", 
		[{"to": endpoint_contract, "input": calldata}, "latest"], 
		rpc, 
		0,
		self, 
		"check_order_validity", 
		{}
		)

func check_order_validity(callback):
	if callback["success"]:
		var valid = callback["result"]
		if valid != "0x0000000000000000000000000000000000000000000000000000000000000000":
			var network_info = Network.network_info.duplicate()
			var rpc = network_info[network]["rpc"]
			Ethers.perform_request(
				"eth_getTransactionCount", 
				[user_address, "latest"], 
				rpc, 
				0, 
				self, 
				"get_tx_count", 
				{}
				)
		else:
			invalid_order()


func get_tx_count(callback):
	if callback["success"]:
		tx_count = callback["result"].hex_to_int()
		var network_info = Network.network_info.duplicate()
		var rpc = network_info[network]["rpc"]
		Ethers.perform_request(
			"eth_gasPrice", 
			[], 
			rpc, 
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
		var endpoint_contract = network_info[network]["endpoint_contract"]
		
		mark_queued_order_as_checked()
		
		var maximum_gas_fee = network_info[network]["maximum_gas_fee"]
		
		#it would be good to perform a gas estimate instead of relying on a maximum gas threshold
		if maximum_gas_fee != "":
			if gas_price > int(maximum_gas_fee):
				gas_fee_too_high()
				return
		
		var key = Ethers.get_key()
		var calldata
		
		if !needs_to_approve:
			main_script.crystal_ball.spawn_message()
			current_tx_type = "order"
			var local_token = FastCcipBot.decode_address(order_in_queue["local_token"])
			
			calldata = "0x" + FastCcipBot.fill_order(key, chain_id, endpoint_contract, rpc, gas_price, tx_count, order_in_queue["message"], local_token)
			
		else:
			current_tx_type = "approval"
			var local_token_contract = approval_in_queue["local_token_contract"]
			
			calldata = "0x" + FastCcipBot.approve_endpoint_allowance(key, chain_id, endpoint_contract, rpc, gas_price, tx_count, local_token_contract)
			
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
				
			var transaction = {
				"network": network,
				"type": current_tx_type,
				"hash": tx_hash
				}
				
			pending_tx = main_script.load_transaction(transaction)
		
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
				pending_tx.was_successful(true, network, block_number)
				if current_tx_type == "approval":
					approval_in_queue["monitorable_token"].get_node("MainPanel/Monitor").text = "Start Monitoring"
					approval_in_queue["monitorable_token"].approved = true
			else:
				print("failed to fill order")
				checking_for_tx_receipt = false	
				order_filling_paused = false
				pending_tx.was_successful(false, network)
				#perhaps would be wise to have a more targeted "get_gas_balance" function
			main_script.get_gas_balances()
	else:
		checking_for_tx_receipt = false	
		rpc_error("failed to check transaction receipt")
			

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
				pending_orders.erase(deletable)
				
