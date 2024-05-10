extends HTTPRequest

# EthRequest can have the following outcomes:

# 1) Successful RPC call returns JSON with "result"; performs callback function on callback node with success
# 2) Failed RPC call; attempts to retry
# 3) Retries exhausted; performs callback function on callback node with failure
# 4) Times out; performs callback function on callback node with failure

var callback = {}
var retry_timer = 0
var prune_timer = 20

func resolve_ethereum_request(result, response_code, headers, body):
	
	if response_code == 200:
		var body_string = body.get_string_from_ascii()
		if body_string.begins_with("{"):
			var get_result = parse_json(body.get_string_from_ascii())
			if typeof(get_result) == 18:
				if get_result.has("result"):
					callback["success"] = true
					callback["result"] = get_result["result"]
			
	if callback["success"]:
		callback()
	else:
		if callback["retries"] < 3:
			callback["retries"] += 1
			retry_timer = 0.2
		else:
			callback()

func callback():
	callback["callback_node"].call(callback["callback_function"], callback)
	queue_free()
	
func _process(delta):
	if retry_timer > 0:
		retry_timer -= delta
		if retry_timer < 0:
			Ethers.perform_request(callback["method"], callback["params"], callback["rpc"], callback["retries"], callback["callback_node"], callback["callback_function"], callback["callback_args"])
			queue_free()
			
	prune_timer -= delta
	if prune_timer < 0:
		callback()
