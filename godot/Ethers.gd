extends Node

# Ethers can handle any Ethereum method, with retries built in.
# If you need calldata, you need to get it from a separate module (such as Ethers-rs via Godot Rust)
# "method" refers to the Ethereum method, while "params" are the method arguments passed as an array
# "callback_args" are application specific, to be used by the callback function along with the result

#Ethers.perform_request("eth_Method", [params], rpc, 0, self, "function", {})

var eth_http_request = preload("res://EthNewRequest.tscn")
var header = "Content-Type: application/json"

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
		"result": {}
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


#ignores structs for now.  They will be application-specific
func get_function_calldata(abi, function_name, args=[]):
	for function in abi:
		if function.has("name"):
			if function["name"] == function_name:
				var function_selector = get_function_selector(function)
				var calldata_string = function_selector 
				var arg_selector = 0
				var offset_shift = 0
				var dynamic_params = []
				var inputs_length = function["inputs"].size()
			
				for input in function["inputs"]:
					var arg = args[arg_selector]
					var parameter
					if !"[" in input["type"]:
						if !input["type"] in ["string", "bytes"]:
							var static_type_call = "encode_" + input["type"]
							parameter = FastCcipBot.call(static_type_call, arg)
						elif input["type"].length() > 5 && input["type"].begins_with("bytes"):
							parameter = encode_fixed_bytes(arg)
						else:
							parameter = get_offset(inputs_length, offset_shift)
							offset_shift += 32
							dynamic_params.append({"arg": arg, "type": input["type"]})
					else:
						if "[]" in input["type"]:
							parameter = get_offset(inputs_length, offset_shift)
							offset_shift += 32
							dynamic_params.append({"arg": arg, "type": input["type"]})
						else:
							parameter = encode_fixed_size_array(arg, input["type"])

					calldata_string += parameter
					arg_selector += 1
				
				for dynamic_param in dynamic_params:
					var parameter
					if !"[" in dynamic_param["type"]:
						match dynamic_param["type"]:
							"string": parameter = encode_string(dynamic_param["arg"])
							"bytes": parameter = encode_dynamic_bytes(dynamic_param["arg"])
					else:
						parameter = encode_dynamic_array(dynamic_param)
					
					calldata_string += parameter

				return calldata_string
	
	return "invalid request"
					
							
						
func get_function_selector(function):
	var selector_string = function["name"] + "("
	for input in function["inputs"]:
		selector_string += input["type"] + ","
	selector_string = selector_string.trim_suffix(",") + ")"
	var selector_bytes = selector_string.to_utf8()
	var function_selector = FastCcipBot.get_function_selector(selector_bytes).left(8)
	return function_selector

func encode_fixed_bytes(arg):
	pass

func encode_fixed_size_array(arg, type):
	pass

func get_offset(length, shift):
	var offset = (32 * length) + shift
	return FastCcipBot.encode_u256(String(offset))

func encode_string(arg):
	pass


#This works when the Bytes are pulled directly from the blockchain
func encode_dynamic_bytes(arg):
	var bytes = FastCcipBot.get_hex_bytes(arg)
	
	#var length = FastCcipBot.encode_u256(String(bytes.size()))
	#var parameter = length
	var filler = 0
	if bytes.size() > 32:
		filler = bytes.size()%32
	
	#parameter += FastCcipBot.old_encode_bytes(bytes)
	
	#AbiEncode automatically adds an unnecessary offset parameter.  
	#but apparently adds a necessary length param? man I don't even know
	var parameter = FastCcipBot.old_encode_bytes(bytes).trim_prefix("0000000000000000000000000000000000000000000000000000000000000020")
	
	if filler != 0:
		parameter += "0".repeat(filler)
	
	return parameter
	

func encode_dynamic_array(dynamic_param):
	#needs to account for fixed bytes as well
	if "string" in dynamic_param["type"] || "bytes" in dynamic_param["type"]:
		return encode_dynamic_array_with_dynamic_values(dynamic_param)
	else:
		return encode_dynamic_array_with_static_values(dynamic_param)


func encode_dynamic_array_with_static_values(dynamic_param):
	var array = dynamic_param["arg"]
	var length = FastCcipBot.encode_u256(String(array.size()))
	var parameter = length
	var static_type_call = "encode_" + dynamic_param["type"]
	#needs to account for fixed bytes as well
	for value in array:
		parameter += FastCcipBot.call(static_type_call, value)
	return parameter
		
		

func encode_dynamic_array_with_dynamic_values(dynamic_param):
	#var length = FastCcipBot.encode_u256(array.size())
	#I'm not quite sure how this is formatted yet
	var parameter
	
	#stuff
	
	return parameter




func get_biguint(minimum, token_decimals):
	if minimum.begins_with("."):
		minimum = "0" + minimum
		
	var zero_filler = int(token_decimals)
	var decimal_index = minimum.find(".")
	var big_uint = minimum
	if decimal_index != -1:
		zero_filler -= minimum.right(decimal_index+1).length()
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





var test_abi = [
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_router",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "_link",
				"type": "address"
			}
		],
		"stateMutability": "nonpayable",
		"type": "constructor"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "router",
				"type": "address"
			}
		],
		"name": "InvalidRouter",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "NoRecursionAllowed",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "OrderAlreadyArrived",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "OrderPathAlreadyFilled",
		"type": "error"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "bytes32",
				"name": "messageId",
				"type": "bytes32"
			}
		],
		"name": "OrderFilled",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "bytes32",
				"name": "messageId",
				"type": "bytes32"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "token",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "ReceivedTokens",
		"type": "event"
	},
	{
		"inputs": [
			{
				"components": [
					{
						"internalType": "bytes32",
						"name": "messageId",
						"type": "bytes32"
					},
					{
						"internalType": "uint64",
						"name": "sourceChainSelector",
						"type": "uint64"
					},
					{
						"internalType": "bytes",
						"name": "sender",
						"type": "bytes"
					},
					{
						"internalType": "bytes",
						"name": "data",
						"type": "bytes"
					},
					{
						"components": [
							{
								"internalType": "address",
								"name": "token",
								"type": "address"
							},
							{
								"internalType": "uint256",
								"name": "amount",
								"type": "uint256"
							}
						],
						"internalType": "struct Client.EVMTokenAmount[]",
						"name": "destTokenAmounts",
						"type": "tuple[]"
					}
				],
				"internalType": "struct Client.Any2EVMMessage",
				"name": "message",
				"type": "tuple"
			}
		],
		"name": "ccipReceive",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			},
			{
				"internalType": "address",
				"name": "_local_token",
				"type": "address"
			}
		],
		"name": "fillOrder",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			},
			{
				"internalType": "address",
				"name": "_endpoint",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "_filler",
				"type": "address"
			},
			{
				"internalType": "address[]",
				"name": "_localTokenList",
				"type": "address[]"
			},
			{
				"internalType": "address[]",
				"name": "_remoteTokenList",
				"type": "address[]"
			},
			{
				"internalType": "uint256[]",
				"name": "_tokenMinimums",
				"type": "uint256[]"
			}
		],
		"name": "filterOrder",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "getRouter",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			}
		],
		"name": "isOrderPathFilled",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes4",
				"name": "interfaceId",
				"type": "bytes4"
			}
		],
		"name": "supportsInterface",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "pure",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "testMessage",
		"outputs": [
			{
				"internalType": "uint64",
				"name": "sourceChainSelector",
				"type": "uint64"
			},
			{
				"internalType": "address",
				"name": "sender",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "receiver",
				"type": "address"
			},
			{
				"internalType": "uint64",
				"name": "sequenceNumber",
				"type": "uint64"
			},
			{
				"internalType": "uint256",
				"name": "gasLimit",
				"type": "uint256"
			},
			{
				"internalType": "bool",
				"name": "strict",
				"type": "bool"
			},
			{
				"internalType": "uint64",
				"name": "nonce",
				"type": "uint64"
			},
			{
				"internalType": "address",
				"name": "feeToken",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "feeTokenAmount",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "data",
				"type": "bytes"
			},
			{
				"internalType": "bytes32",
				"name": "messageId",
				"type": "bytes32"
			}
		],
		"stateMutability": "view",
		"type": "function"
	}
]
