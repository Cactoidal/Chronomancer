extends Control


var order_processor = preload("res://OrderProcessor.tscn")
var monitorable_token = preload("res://MonitorableToken.tscn")
var sent_transaction = preload("res://SentTransaction.tscn")

var crystal_ball

var monitorable_tokens = []
var active_monitored_tokens = []

var active = false

func initialize():
	active = true
	crystal_ball = get_parent().get_node("ChronomancerLogo/LogoPivot")
	$LoadSavedTokens.connect("pressed", self, "load_saved_tokens")
	$LoadDemo.connect("pressed", self, "load_demo")
	for network in Network.network_info.keys():
		var new_processor = order_processor.instance()
		Network.network_info[network]["order_processor"] = new_processor
		new_processor.network = network
		new_processor.main_script = self
		$OrderProcessors.add_child(new_processor)

var log_timer = 1

func _process(delta):
	if active:
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
		Ethers.perform_request(
			"eth_blockNumber", 
			[], 
			Network.network_info[network]["rpc"], 
			0, 
			self, 
			"update_block_number", 
			{"network": network}
			)
		
func check_for_ccip_messages(callback):
	if callback["success"]:
		
		var from_network = callback["callback_args"]["network"]
		
		for event in callback["result"]:
			
			var message = event["data"].right(2)
			var onramp = event["address"]
				
			var onramp_list = Network.network_info[from_network]["onramp_contracts_by_network"].duplicate()
			var to_network
			for network in onramp_list:
				if network["contract"] != onramp:
					network["contract"] = network["contract"].to_lower()
				if network["contract"] == onramp:
					to_network = network["network"]
			
			if to_network != null:
				print(from_network + " sent message to " + to_network)
				Network.network_info[to_network]["order_processor"].intake_message(message, from_network)


func check_endpoint_allowance(callback):
	if callback["success"]:
		var network = callback["callback_args"]["network"]
		var local_token_contract = callback["callback_args"]["local_token_contract"]
		var endpoint_contract = callback["callback_args"]["endpoint_contract"]
		
		var allowance = callback["result"]
		if allowance != "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff":
			var order_filler = Network.network_info[network]["order_processor"].get_node("OrderFiller")
			print(network + " endpoint " + endpoint_contract + " needs approval to spend local token " + local_token_contract)
			order_filler.needs_to_approve = true
			order_filler.pending_approvals.append(
				{
					"endpoint_contract": endpoint_contract, 
					"local_token_contract": local_token_contract,
					"monitorable_token": callback["callback_args"]["monitorable_token"]
				}
			)
			callback["callback_args"]["monitorable_token"].get_node("MainPanel/Monitor").text = "Approving..."
		else:
			print(network + " endpoint " + endpoint_contract + " has allowance to spend local token " + local_token_contract)
			callback["callback_args"]["monitorable_token"].approved = true


func get_gas_balances():
	for network in Network.network_info.keys():
		Ethers.perform_request(
			"eth_getBalance", 
			[Ethers.user_address, "latest"], 
			Network.network_info[network]["rpc"], 
			0, 
			self, 
			"update_balance", 
			{"network": network}
			)


var token_downshift = 0
func add_monitored_token(new_monitored_token):
	var serviced_network = new_monitored_token["serviced_network"]
	var local_token_contract = new_monitored_token["local_token_contract"]
	var endpoint_contract = new_monitored_token["endpoint_contract"]

	save_token(new_monitored_token)
	
	if !check_for_token_match(new_monitored_token):
		
		var instanced_monitorable_token = monitorable_token.instance()
		new_monitored_token["token_node"] = instanced_monitorable_token
		Network.network_info[serviced_network]["monitored_tokens"].append(new_monitored_token)
		monitorable_tokens.append(new_monitored_token)
		
		instanced_monitorable_token.load_info(self, new_monitored_token)
		
		$MonitoredTokenList/MonitoredTokenScroll/MonitoredTokenContainer.add_child(instanced_monitorable_token)
		instanced_monitorable_token.rect_position.y += token_downshift
		token_downshift += 270
		$MonitoredTokenList/MonitoredTokenScroll/MonitoredTokenContainer.rect_min_size.y += 270
		
		#check token approval
		var chain_id = int(Network.network_info[serviced_network]["chain_id"])
		var rpc = Network.network_info[serviced_network]["rpc"]
		
		var key = Ethers.get_key()
		
		var calldata = FastCcipBot.check_endpoint_allowance(key, chain_id, rpc, local_token_contract, endpoint_contract)
		var params = [{"to": local_token_contract, "input": calldata}, "latest"]
		var callback_args = {
			"network": serviced_network, 
			"function_name": "check_endpoint_allowance", 
			"local_token_contract": local_token_contract, 
			"endpoint_contract": endpoint_contract, 
			"monitorable_token": instanced_monitorable_token
			}
			
		Ethers.perform_request(
			"eth_call", 
			params, 
			rpc, 0, 
			self, 
			"check_endpoint_allowance", 
			callback_args
			)
		
		get_gas_balances()


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
	var new_content = {"tokens": []}
	var prev_content
	var file = File.new()
	if file.file_exists("user://saved_tokens"):
		file.open("user://saved_tokens", File.READ)
		prev_content = parse_json(file.get_as_text())
		file.close()
	
	file.open("user://saved_tokens", File.WRITE)
	
	if prev_content != null:
		if !prev_content["tokens"].empty():
			var token_address = token["local_token_contract"]
			var token_network = token["serviced_network"]
			var match_found = false
			for saved_token in prev_content["tokens"]:
				if saved_token["local_token_contract"] == token_address && saved_token["serviced_network"] == token_network:
					new_content["tokens"].append(token)
					match_found = true
				else:
					new_content["tokens"].append(saved_token)
			if !match_found:
				new_content["tokens"].append(token)
		else:
			new_content["tokens"].append(token)
	else:
			new_content["tokens"].append(token)
	
	file.store_string(JSON.print(new_content))
	file.close()

func load_saved_tokens():
	var file = File.new()
	if file.file_exists("user://saved_tokens"):
		file.open("user://saved_tokens", File.READ)
		var content = parse_json(file.get_as_text())
		if content != null:
			for token in content["tokens"]:
				add_monitored_token(token)
		file.close()

func check_for_token_match(token):
	var token_address = token["local_token_contract"]
	var token_network = token["serviced_network"]
	for monitored_token in monitorable_tokens:
		if monitored_token["local_token_contract"] == token_address && monitored_token["serviced_network"] == token_network:
			var token_node = monitored_token["token_node"]
			monitored_token = token
			monitored_token["token_node"] = token_node
			token_node.load_info(self, monitored_token)
			for network_token in Network.network_info[token_network]["monitored_tokens"]:
				if network_token["local_token_contract"] == token_address:
					network_token = monitored_token
			return true
	return false

func update_balance(callback):
	if callback["success"]:
		var balance = String(callback["result"].hex_to_int())
		var network = callback["callback_args"]["network"]
		Network.network_info[network]["gas_balance"] = balance
		for token in monitorable_tokens:
			if token["serviced_network"] == network:
				var node = token["token_node"]
				node.update_balances(balance)


func update_block_number(callback):
	if callback["success"]:
		var latest_block = callback["result"]
		var network = callback["callback_args"]["network"]
		var previous_block = Network.network_info[network]["latest_block"] 
		var params = {"fromBlock": previous_block, "address": Network.network_info[network]["onramp_contracts"].duplicate(), "topics": ["0xd0c3c799bf9e2639de44391e7f524d229b2b55f5b1ea94b2bf7da42f7243dddd"]}
		if previous_block != "latest":
			params["toBlock"] = latest_block
			
			Ethers.perform_request(
				"eth_getLogs", 
				[params], 
				Network.network_info[network]["rpc"], 
				0, 
				self, 
				"check_for_ccip_messages",
				{"network": network}
				)
			
		Network.network_info[network]["latest_block"] = latest_block
		
		
		



func load_demo():
	var tokens = []
	var new_token = {
		"serviced_network": "Ethereum Sepolia",
		"local_token_contract": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
		"token_name": "CCIP-BnM",
		"token_decimals": "18",
		"monitored_networks": {
			"Optimism Sepolia": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
			"Arbitrum Sepolia": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
			"Base Sepolia": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e"
		},
		"endpoint_contract":"0xD9E254783C240ece646C00e2D3c1Fb6Eb0215749",
		"minimum": "0",
		"gas_balance": "0",
		"token_balance": "0",
		"token_node": ""
	}
	
	tokens.append(new_token.duplicate())
	
	var new_token2 = {
		"serviced_network": "Optimism Sepolia",
		"local_token_contract": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
		"token_name": "CCIP-BnM",
		"token_decimals": "18",
		"monitored_networks": {
			"Ethereum Sepolia": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
			"Arbitrum Sepolia": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
			"Base Sepolia": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e"
		},
		"endpoint_contract":"0x8b98E266f5983084Fe5813E3d729391056c15692",
		"minimum": "0",
		"gas_balance": "0",
		"token_balance": "0",
		"token_node": ""
	}
	
	tokens.append(new_token2.duplicate())
	
	var new_token3 = {
		"serviced_network": "Arbitrum Sepolia",
		"local_token_contract": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"token_name": "CCIP-BnM",
		"token_decimals": "18",
		"monitored_networks": {
			"Ethereum Sepolia": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
			"Optimism Sepolia": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
			"Base Sepolia": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e"
		},
		"endpoint_contract":"0x69487b0e0CF57Ad6b4339cda70a45b4aDB8eef08",
		"minimum": "0",
		"gas_balance": "0",
		"token_balance": "0",
		"token_node": ""
	}
	
	tokens.append(new_token3.duplicate())
	
	var new_token4 = {
		"serviced_network": "Base Sepolia",
		"local_token_contract": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e",
		"token_name": "CCIP-BnM",
		"token_decimals": "18",
		"monitored_networks": {
			"Ethereum Sepolia": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
			"Optimism Sepolia": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
			"Arbitrum Sepolia": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		},
		"endpoint_contract":"0xC3E1D898D09511AD47842607779985BD95018DE2",
		"minimum": "0",
		"gas_balance": "0",
		"token_balance": "0",
		"token_node": ""
	}
	
	tokens.append(new_token4.duplicate())
	
	for token in tokens:
		add_monitored_token(token.duplicate())
