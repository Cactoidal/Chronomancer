extends HTTPRequest


var prune_timer = 10

var request_type
var main_script
var network
var extra_args = {}

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
