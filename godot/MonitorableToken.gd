extends Control

var main_script
var http
var monitorable_token
var approved = false
var monitoring = false
var eth_http_request = preload("res://EthRequest.tscn")

var header = "Content-Type: application/json"

func _ready():
	$MainPanel/Monitor.connect("pressed", self, "toggle_monitor")
	$MainPanel/Close.connect("pressed", self, "close")
	$CloseOverlay/ClosePanel/Cancel.connect("pressed", self, "cancel_close")
	$CloseOverlay/ClosePanel/Remove.connect("pressed", self, "confirm_close")

func load_info(main, token):
	monitorable_token = token
	main_script = main
	http = main_script.get_node("HTTP")
	var network = monitorable_token["serviced_network"]
	var token_name = monitorable_token["token_name"]
	var monitored_networks = monitorable_token["monitored_networks"]
	var token_decimals = monitorable_token["token_decimals"] 
	var minimum = main_script.convert_to_smallnum(monitorable_token["minimum"], token_decimals)
	var gas_balance = monitorable_token["gas_balance"]
	var token_balance = monitorable_token["token_balance"]
	var network_info = main_script.network_info.duplicate()
	
	$MainPanel/NetworkLogo.texture = load(network_info[network]["logo"])
	
	
	for old_logo in $MonitoredNetworks.get_children():
		old_logo.queue_free()
	var shift = 0
	for monitored_network in monitored_networks:
		var new_logo = TextureRect.new()
		new_logo.texture = load(network_info[monitored_network]["logo"])
		$MonitoredNetworks.add_child(new_logo)
		new_logo.rect_position.x += shift
		shift += 75
	
	$MainPanel/Label.text = "Providing fast transfers of\n" + token_name + "\non " + network + ". \nMinimum: " + String(minimum) + "\n\nMonitoring transfers from:"

	
func toggle_monitor():
	if !approved:
		return
		
	if !monitoring:
		$MainPanel/Monitor.text = "Stop Monitoring"
		monitoring = true
		main_script.active_monitored_tokens.append(monitorable_token)
	
	elif monitoring:
		$MainPanel/Monitor.text = "Start Monitoring"
		monitoring = false
		main_script.active_monitored_tokens.erase(monitorable_token)

func close():
	$CloseOverlay.visible = true

func cancel_close():
	$CloseOverlay.visible = false

func confirm_close():
	var network = monitorable_token["serviced_network"]
	if monitoring:
		toggle_monitor()
	
	var index = 0
	var delete_index = 0
	for token in main_script.network_info[network]["monitored_tokens"]:
		if token["local_token_contract"] == monitorable_token["local_token_contract"]:
			delete_index = index
		index += 1
	main_script.network_info[network]["monitored_tokens"].remove(delete_index)
	
	index = 0
	for token in main_script.monitorable_tokens:
		if token["local_token_contract"] == monitorable_token["local_token_contract"]:
			delete_index = index
		index += 1
	main_script.monitorable_tokens.remove(delete_index)
	
	var suspended_nodes = main_script.monitorable_tokens
	main_script.token_downshift = 0
	main_script.get_node("MonitoredTokenList/MonitoredTokenScroll/MonitoredTokenContainer").rect_min_size.y -= (270 * (suspended_nodes.size() + 1))
	
	for node in suspended_nodes:
		node["token_node"].rect_position.y = 0
		node["token_node"].rect_position.y += main_script.token_downshift
		main_script.token_downshift += 270
		main_script.get_node("MonitoredTokenList/MonitoredTokenScroll/MonitoredTokenContainer").rect_min_size.y += 270
	
	queue_free()

func update_balances(balance):
	monitorable_token["gas_balance"] = balance
	$MainPanel/GasBalance.text = monitorable_token["serviced_network"] + " Gas Balance: " + main_script.convert_to_smallnum(balance, 18)
	get_erc20_balance(monitorable_token["serviced_network"], monitorable_token["local_token_contract"])
	
	


func get_erc20_balance(network, token_contract):
	var network_info = main_script.network_info.duplicate()
	var rpc = network_info[network]["rpc"]
	var chain_id = int(network_info[network]["chain_id"])
	var file = File.new()
	file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, main_script.password)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.check_token_balance(content, chain_id, rpc, token_contract)
	perform_ethereum_request(network, "eth_call", [{"to": token_contract, "input": calldata}, "latest"], {"function_name": "check_token_balance", "token_contract": token_contract})

func perform_ethereum_request(network, method, params, extra_args={}):
	var network_info = main_script.network_info.duplicate()
	var rpc = network_info[network]["rpc"]
	
	var http_request = eth_http_request.instance()
	http.add_child(http_request)
	http_request.network = network
	http_request.request_type = method
	http_request.main_script = self
	http_request.extra_args = extra_args
	http_request.connect("request_completed", http_request, "resolve_ethereum_request")
	
	var tx = {"jsonrpc": "2.0", "method": method, "params": params, "id": 7}
	
	http_request.request(rpc, 
	[header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func resolve_ethereum_request(network, method, get_result, extra_args):
	match method:
		"eth_call": update_erc20_balance(get_result)

func update_erc20_balance(get_result):
	if "result" in get_result.keys():
		var balance = FastCcipBot.decode_u256(get_result["result"])
		monitorable_token["token_balance"] = balance
		var token_decimals = monitorable_token["token_decimals"]
		$MainPanel/TokenBalance.text = monitorable_token["token_name"] + " Balance:\n" + main_script.convert_to_smallnum(balance, token_decimals)
		


func ethereum_request_failed(network, method, extra_args):
	pass
