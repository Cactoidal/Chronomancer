extends HTTPRequest


var prune_timer = 300

var request_type
var main_script
var network
var extra_args = {}

var potential_order
var network_info


func _ready():
	pass
	

func check_order_validity():
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





func resolve_ethereum_request(result, response_code, headers, body):
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		main_script.resolve_ethereum_request(network, request_type, get_result, extra_args)
		queue_free()
	else:
		main_script.ethereum_request_failed(network, request_type, extra_args)
		queue_free()

func _process(delta):
	prune_timer -= delta
	if prune_timer < 0:
		main_script.ethereum_request_failed(network, request_type, extra_args)
		queue_free()
