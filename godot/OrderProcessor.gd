extends HTTPRequest

var header = "Content-Type: application/json"

var main_script
var network_info
var user_address

var pending_messages = []
var message_filtering_paused = false

var message_in_queue

func _ready():
	self.connect("request_completed", self, "resolve_ethereum_request")

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
		print("got message")
		print("going to " + network_info["rpc"])
		pending_messages.append({
			"message": message,
			"checked": false, 
			"time_to_prune": 240,
			"from_network": from_network})

func filter_orders():
	if !pending_messages.empty():
		for pending_message in pending_messages:
			if pending_message["checked"] == false && !message_filtering_paused:
				message_filtering_paused = true
				pending_message["checked"] = true
				message_in_queue = pending_message
				compose_message(pending_message["message"], pending_message["from_network"])
				print("composing message")

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
	
	print(get_result)
	if response_code == 200 && get_result.has("result"):
		print("checked validity:")
		print(get_result)
		var valid = FastCcipBot.decode_bool(get_result["result"])
		if valid == "true":
			$OrderFiller.intake_order(message_in_queue.duplicate())
			print("sent order to filler")
		else:
			print("invalid order")
	else:
		print("invalid order")
	
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
				print("old message timed out")
				pending_messages.erase(deletable)
	
