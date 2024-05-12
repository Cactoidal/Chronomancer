extends Node

var main_script
var network

var pending_messages = []
var message_filtering_paused = false

var message_in_queue

func _process(delta):
	filter_orders()
	prune_pending_messages(delta)

func intake_message(message, from_network):
	var is_new_message = true
	if !pending_messages.empty():
		for pending_message in pending_messages:
			if pending_message["message"] == message:
				is_new_message = false
	if is_new_message:
		var network_info = Network.network_info.duplicate()
		
		pending_messages.append(
			{
			"message": message,
			"checked": false, 
			"time_to_prune": 240,
			"from_network": from_network,
			"local_token": ""
			}
			)

func filter_orders():
	if !pending_messages.empty():
		for pending_message in pending_messages:
			if pending_message["checked"] == false && !message_filtering_paused:
				message_filtering_paused = true
				pending_message["checked"] = true
				message_in_queue = pending_message
				compose_message(pending_message["message"], pending_message["from_network"])

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
		rpc, 
		message, 
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
		"check_message_validity", 
		{}
		)
	

func check_message_validity(callback):
	if callback["success"]:
		var valid = callback["result"]
		if valid != "0x0000000000000000000000000000000000000000000000000000000000000000":
			message_in_queue["local_token"] = valid
			$OrderFiller.intake_order(message_in_queue.duplicate())
	
	message_filtering_paused = false


func prune_pending_messages(delta):
	if !pending_messages.empty():
		var deletion_queue = []
		for pending_message in pending_messages:
			pending_message["time_to_prune"] -= delta
			if pending_message["time_to_prune"] < 0:
				deletion_queue.append(pending_message)
		if !deletion_queue.empty():
			for deletable in deletion_queue:
				pending_messages.erase(deletable)
	
