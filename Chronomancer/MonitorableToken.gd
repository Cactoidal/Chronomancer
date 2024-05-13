extends Control

var main_script
var monitorable_token
var approved = false
var monitoring = false

func _ready():
	$MainPanel/Monitor.connect("pressed", self, "toggle_monitor")
	$MainPanel/Close.connect("pressed", self, "close")
	$CloseOverlay/ClosePanel/Cancel.connect("pressed", self, "cancel_close")
	$CloseOverlay/ClosePanel/Remove.connect("pressed", self, "confirm_close")

func load_info(main, token):
	monitorable_token = token
	main_script = main
	var network = monitorable_token["serviced_network"]
	var token_name = monitorable_token["token_name"]
	var monitored_networks = monitorable_token["monitored_networks"]
	var token_decimals = monitorable_token["token_decimals"] 
	var minimum = Ethers.convert_to_smallnum(monitorable_token["minimum"], token_decimals)
	var gas_balance = monitorable_token["gas_balance"]
	var token_balance = monitorable_token["token_balance"]
	var network_info = Network.network_info.duplicate()
	
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
	for token in Network.network_info[network]["monitored_tokens"]:
		if token["local_token_contract"] == monitorable_token["local_token_contract"]:
			delete_index = index
		index += 1
	Network.network_info[network]["monitored_tokens"].remove(delete_index)
	
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
	$MainPanel/GasBalance.text = monitorable_token["serviced_network"] + " Gas Balance: " + Ethers.convert_to_smallnum(balance, 18)
	get_erc20_balance(monitorable_token["serviced_network"], monitorable_token["local_token_contract"])


func get_erc20_balance(network, token_contract):
	var network_info = Network.network_info.duplicate()
	var rpc = network_info[network]["rpc"]
	var chain_id = int(network_info[network]["chain_id"])
	var key = Ethers.get_key()
	var calldata = FastCcipBot.check_token_balance(key, chain_id, rpc, token_contract)
	Ethers.perform_request(
		"eth_call", 
		[{"to": token_contract, "input": calldata}, "latest"], 
		network_info[network]["rpc"], 
		0, 
		self, 
		"update_erc20_balance", 
		{}
		)


func update_erc20_balance(callback):
	if callback["success"]:
		var balance = FastCcipBot.decode_u256(callback["result"])
		monitorable_token["token_balance"] = balance
		var token_decimals = monitorable_token["token_decimals"]
		$MainPanel/TokenBalance.text = monitorable_token["token_name"] + " Balance:\n" + Ethers.convert_to_smallnum(balance, token_decimals)
		
