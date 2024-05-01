extends HTTPRequest

var header = "Content-Type: application/json"

var main_script
var network_info

var pending_messages = []
var pause_message_filtering = false

var message_in_queue

func _ready():
	self.connect("request_completed", self, "resolve_ethereum_request")

func _process(delta):
	filter_orders()
	prune_pending_messages(delta)

func intake_message(message):
	var is_new_message = true
	if !pending_messages.empty():
		for pending_message in pending_messages:
			if pending_message["message"] == message:
				is_new_message = false
	if is_new_message:
		pending_messages.append({
			"message": message,
			"checked": false, 
			"time_to_prune": 240})

func filter_orders():
	if !pending_messages.empty():
		for pending_message in pending_messages:
			if pending_message["checked"] == false && !pause_message_filtering:
				pause_message_filtering = true
				pending_message["checked"] = true
				compose_message(pending_message["message"])

func compose_message(message):
	message_in_queue = message
	var rpc = network_info["rpc"]
	var chain_id = network_info["chain_id"]
	var destination_selector = network_info["chain_selector"]
	var endpoint_contract = network_info["endpoint_contract"]
	var monitored_tokens = network_info["monitored_tokens"]
	
	var token_list = []
	var token_minimum_list = []
	
	for token in monitored_tokens:
		token_list.append(token["token_contract"])
		token_minimum_list.append(token["minimum"])
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.filter_order(content, chain_id, endpoint_contract, rpc, message, destination_selector, token_list, token_minimum_list)
	
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
	
	if response_code == 200:
		var valid = FastCcipBot.decode_bool(get_result)
		if valid:
			$OrderFiller.intake_order(message_in_queue.duplicate())
			print("sent order to filler")
		else:
			pass
	else:
		pass
	
	pause_message_filtering = false

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
				print("pending message timed out")
	
