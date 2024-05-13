extends Node

# Ethers can handle any Ethereum method, with retries built in.
# If you need calldata, you need to get it from a separate module (such as Ethers-rs via Godot Rust)
# "method" refers to the Ethereum method, while "params" are the method arguments passed as an array
# "callback_args" are application specific, to be used by the callback function along with the result

var eth_http_request = preload("res://EthRequest.tscn")
var header = "Content-Type: application/json"

var password
var user_address

func perform_request(method, params, rpc, retries, callback_node, callback_function, callback_args={}):
	
	var callback = {
		"callback_node": callback_node,
		"callback_function": callback_function,
		"callback_args": callback_args,
		"rpc": rpc,
		"method": method,
		"params": params,
		"success": false,
		"retries": retries,
		"result": "error"
	}
	
	var http_request = eth_http_request.instance()
	
	http_request.callback = callback
	http_request.connect("request_completed", http_request, "resolve_ethereum_request")
	add_child(http_request)
	
	var tx = {"jsonrpc": "2.0", "method": method, "params": params, "id": 7}
	
	http_request.request(rpc, 
	[header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func get_key():
	var file = File.new()
	file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
	var key = file.get_buffer(32)
	file.close()
	return key

func get_address():
	user_address = FastCcipBot.get_address(get_key())

func get_biguint(number, token_decimals):
	if number.begins_with("."):
		number = "0" + number
		
	var zero_filler = int(token_decimals)
	var decimal_index = number.find(".")
	var big_uint = number
	if decimal_index != -1:
		zero_filler -= number.right(decimal_index+1).length()
		big_uint.erase(decimal_index,decimal_index)
			
	for zero in range(zero_filler):
		big_uint += "0"
	
	var zero_parse_index = 0
	if big_uint.begins_with("0"):
		for digit in big_uint:
			if digit == "0":
				zero_parse_index += 1
			else:
				break
	big_uint = big_uint.right(zero_parse_index)

	if big_uint == "":
		big_uint = "0"

	return big_uint


func convert_to_smallnum(bignum, token_decimals):
	var size = bignum.length()
	var new_smallnum = ""
	if size <= int(token_decimals):
		new_smallnum = "0."
		var fill_length = int(token_decimals) - size
		for zero in range(fill_length):
			new_smallnum += "0"
		new_smallnum += String(bignum)
	elif size > 18:
		new_smallnum = bignum
		var decimal_index = size - 18
		new_smallnum = new_smallnum.insert(decimal_index, ".")
	
	var index = 0
	var zero_parse_index = 0
	var prune = false
	for digit in new_smallnum:
		if digit == "0":
			if !prune:
				zero_parse_index = index
				prune = true
		else:
			prune = false
		index += 1
	if prune:
		new_smallnum = new_smallnum.left(zero_parse_index).trim_suffix(".")
	
	return new_smallnum
