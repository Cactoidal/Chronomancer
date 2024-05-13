extends Button

var start_pos
var slide_pos
var slid_out = false
var sliding = false

var color_empty = Color(1, 1, 1, 0)
var color_white = Color(1, 1, 1, 0.4)
var color_red = Color(1, 0, 0, 0.4)
var color_green = Color(0, 1, 0, 0.4)
var color_yellow = Color(1, 1, 0, 0.4)

var main_script
var scan_link
var overlay
var settings_slider

var choosing_service_network = false
var choosing_monitored_networks = false
var choosing_minimum = false
var confirming_choices = false

var previous_token_address
var previous_token_length = 0

var new_token = {
		"serviced_network": "",
		"local_token_contract": "",
		"token_name": "",
		"token_decimals": "",
		"monitored_networks": {

		},
		"endpoint_contract":"",
		"minimum": 0,
		"gas_balance": 0,
		"token_balance": 0,
		"token_node": ""
}

var pending_token = {}

func _ready():
	main_script = get_parent()
	overlay = main_script.get_node("Overlay")
	settings_slider = main_script.get_node("Settings")
	start_pos = rect_position
	slide_pos = rect_position
	slide_pos.x += 353
	pending_token = new_token.duplicate()
	self.connect("pressed", self, "slide")
	$Confirm.connect("pressed", self, "confirm_choices")
	$AddNetwork.connect("pressed", self, "add_monitored_network")
	$ScanLink/ScanLink.connect("pressed", self, "open_scanner_link")
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			button.connect("pressed", self, "pick_network", [button.name])
			button.connect("mouse_entered", self, "highlight_button", [button.name])
			button.connect("mouse_exited", self, "highlight_button", [button.name])

func slide():
	if !slid_out && !sliding:
		overlay.visible = true
		slid_out = true
		sliding = true
		$SlideTween.interpolate_property(self, "rect_position", start_pos, slide_pos, 1, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$SlideTween.start()
	elif slid_out && !sliding:
		if !settings_slider.slid_out:
			overlay.visible = false
		slid_out = false
		sliding = true
		$SlideTween.interpolate_property(self, "rect_position", slide_pos, start_pos, 1, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$SlideTween.start()

func _process(delta):
	
	if $AddressEntry.text.length() != previous_token_length || $AddressEntry.text != previous_token_address:
		$ScanLink.visible = false
		previous_token_length = $AddressEntry.text.length()
		previous_token_address = $AddressEntry.text
		if previous_token_length == 42 && $NetworkLabel.text != "":
			get_erc20_name($NetworkLabel.text, $AddressEntry.text)
			if choosing_service_network:
				get_erc20_decimals($NetworkLabel.text, $AddressEntry.text)
		else:
			$TokenLabel.text = ""
			$TokenBalance.text = ""
	
	if sliding && !$SlideTween.is_active():
		sliding = false
		if slid_out:
			text = "Cancel"
			start_new()
		else:
			text = "Add Token"
			clear_all()
		

func start_new():
	pending_token = new_token.duplicate()
	choosing_service_network = true
	pending_token["monitored_networks"] = {}
	

func pick_network(network):
	if choosing_service_network:
		var network_info = Network.network_info.duplicate()
		pending_token["serviced_network"] = network
		
		pending_token["endpoint_contract"] = network_info[network]["endpoint_contract"]
		get_button_overlay(network).color = color_red
		wipe_buttons()
		clear_text()
		$NetworkLabel.text = network
		Ethers.perform_request(
			"eth_getBalance", 
			[Ethers.user_address, "latest"], 
			network_info[network]["rpc"], 
			0, 
			self, 
			"load_network_gas", 
			{"network": network}
			)
		
	elif choosing_monitored_networks && network != pending_token["serviced_network"]:
		wipe_buttons()
		clear_text()
		if get_button_overlay(network).color != color_green:
			get_button_overlay(network).color = color_yellow
		$NetworkLabel.text = network
		if network in pending_token["monitored_networks"].keys():
			$AddressEntry.text = pending_token["monitored_networks"].duplicate()[network]
			get_erc20_name(network, $AddressEntry.text)


func confirm_choices():
	if choosing_service_network:
		if pending_token["serviced_network"] != "" && $TokenLabel.text != "" && $AddressEntry.text.length() == 42 && float($GasBalance.text.right(9)) > 0 && float($TokenBalance.text.right(9)) > 0:
			pending_token["local_token_contract"] = $AddressEntry.text
			pending_token["token_name"] = $TokenLabel.text
			clear_text()
			choosing_service_network = false
			choosing_monitored_networks = true
			$Prompt.text = "Provide remote token addresses\nfor each network to monitor."
			$AddNetwork.visible = true
	elif choosing_monitored_networks == true && !pending_token["monitored_networks"].keys().empty():
		clear_text()
		$AddNetwork.visible = false
		choosing_minimum = true
		choosing_monitored_networks = false
		$AddressEntry.text = "0"
		$Prompt.text = "Set the transfer minimum."
	elif choosing_minimum && $AddressEntry.text.is_valid_float():
		var minimum = $AddressEntry.text
		var token_decimals = pending_token["token_decimals"]
		var error = filter_decimals(minimum, token_decimals)
		if error:
			return
		pending_token["minimum"] = Ethers.get_biguint(minimum, token_decimals)
		clear_text()
		$AddressEntry.visible = false
		$Prompt.text = ""
		var network_list_string = ""
		for network in pending_token["monitored_networks"].duplicate().keys():
			network_list_string += network + "\n"
			#token_name
		$FinalConfirm.text = "You will provide fast transfers of\n" + pending_token["token_name"] + "\non " + pending_token["serviced_network"] + "\nby monitoring incoming traffic from:\n\n" + network_list_string + "\nAnd will only serve transactions with a \nminimum transfer of " + minimum + " tokens."
		#$FinalConfirm.text = "You will provide fast transfers to " + pending_token["serviced_network"] + ",\nby monitoring incoming traffic from:\n\n" + network_list_string + "\nAnd will only serve transactions with a \nminimum transfer of " + minimum + " tokens."
		choosing_minimum = false
		confirming_choices = true
	elif confirming_choices:
		main_script.add_monitored_token(pending_token.duplicate())
		slide()

func add_monitored_network():
	var network = $NetworkLabel.text
	var token_name = $TokenLabel.text
	if network != "" && token_name != "" && $AddressEntry.text.length() == 42 && token_name == pending_token["token_name"]:
		get_button_overlay(network).color = color_green
		pending_token["monitored_networks"][network] = $AddressEntry.text
		clear_text()

func clear_text():
	previous_token_length = 0
	$TokenLabel.text = ""
	$NetworkLabel.text = ""
	$AddressEntry.text = ""
	$GasBalance.text = ""
	$TokenBalance.text = ""
	$ScanLink.visible = false
	$FinalConfirm.text = ""
	
func clear_all():
	clear_text()
	$AddNetwork.visible = false
	$Prompt.text = "Choose a network to serve and\nprovide your token's local address.\nYou must have a balance to provide\nfast transfers."
	choosing_service_network = false
	choosing_monitored_networks = false
	choosing_minimum = false
	confirming_choices = false
	pending_token = new_token.duplicate()
	pending_token["monitored_tokens"] = {}
	wipe_buttons()
	$AddressEntry.visible = true
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			button.get_node("Overlay").color = color_empty
			

func wipe_buttons():
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			if button.name != pending_token["serviced_network"] && !button.name in pending_token["monitored_networks"].keys():
				button.get_node("Overlay").color = color_empty

func get_button_overlay(network):
	for button in $NetworkButtons.get_children():
		if button.name == network:
			return button.get_node("Overlay")

func highlight_button(network):
	if network != pending_token["serviced_network"] && !network in pending_token["monitored_networks"].keys():
		if get_button_overlay(network).color == color_empty:
			#wipe_buttons()
			get_button_overlay(network).color = color_white
		elif get_button_overlay(network).color != color_yellow:
			get_button_overlay(network).color = color_empty
	
func get_erc20_name(network, token_contract):
	var network_info = Network.network_info.duplicate()
	var chain_id = network_info[network]["chain_id"]
	var rpc = network_info[network]["rpc"]
	var key = Ethers.get_key()
	var calldata = FastCcipBot.get_token_name(key, chain_id, rpc, token_contract)
	Ethers.perform_request(
		"eth_call", 
		[{"to": token_contract, "input": calldata}, "latest"], 
		network_info[network]["rpc"], 
		0, 
		self, 
		"load_token_data", 
		{"network": network, 
		"function_name": "get_token_name", "token_contract": token_contract}
		)
	
func get_erc20_balance(network, token_contract):
	var network_info = Network.network_info.duplicate()
	var chain_id = network_info[network]["chain_id"]
	var rpc = network_info[network]["rpc"]
	var key = Ethers.get_key()
	var calldata = FastCcipBot.check_token_balance(key, chain_id, rpc, token_contract)
	Ethers.perform_request(
		"eth_call", 
		[{"to": token_contract, "input": calldata}, "latest"], 
		network_info[network]["rpc"], 
		0, 
		self, 
		"load_token_data", 
		{"network": network, "function_name": "check_token_balance", "token_contract": token_contract}
		)


func get_erc20_decimals(network, token_contract):
	var network_info = Network.network_info.duplicate()
	var chain_id = network_info[network]["chain_id"]
	var rpc = network_info[network]["rpc"]
	var key = Ethers.get_key()
	var calldata = FastCcipBot.get_token_decimals(key, chain_id, rpc, token_contract)
	Ethers.perform_request(
		"eth_call", 
		[{"to": token_contract, "input": calldata}, "latest"], 
		network_info[network]["rpc"], 
		0, 
		self,
		"load_token_data", 
		{"network": network, "function_name": "get_token_decimals", "token_contract": token_contract}
		)


func load_network_gas(callback):
	if callback["success"]:
		var balance = String(callback["result"].hex_to_int())
		pending_token["gas_balance"] = balance
		$GasBalance.text = "Balance: " + Ethers.convert_to_smallnum(balance, 18)
		
	
func load_token_data(callback):
	if callback["success"]:
		var args = callback["callback_args"]
		if args["function_name"] == "get_token_name":
			if callback["result"] != "0x":
				$TokenLabel.text = FastCcipBot.decode_hex_string(callback["result"])
				var network_info = Network.network_info.duplicate()
				scan_link = network_info[args["network"]]["scan_url"] + "address/" + $AddressEntry.text
				$ScanLink.visible = true
		
		if args["function_name"] == "get_token_decimals":
			if callback["result"] != "0x":
				var token_decimals = FastCcipBot.decode_u8(callback["result"])
				pending_token["token_decimals"] = token_decimals
				get_erc20_balance($NetworkLabel.text, $AddressEntry.text)
					
		if args["function_name"] == "check_token_balance":
			if callback["result"] != "0x":
				var balance = FastCcipBot.decode_u256(callback["result"])
				pending_token["token_balance"] = balance
				var token_decimals = pending_token["token_decimals"]
				$TokenBalance.text = "Balance: " + Ethers.convert_to_smallnum(balance, token_decimals)
			else:
				$TokenBalance.text = ""
		else:
			$TokenBalance.text = ""
	
func open_scanner_link():
	OS.shell_open(scan_link)


func filter_decimals(minimum, token_decimals):
	var decimal_index = minimum.find(".")
	if decimal_index != -1:
		if minimum.right(decimal_index).length() > token_decimals:
			return true
	return false
