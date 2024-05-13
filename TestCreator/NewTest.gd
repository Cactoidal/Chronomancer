extends Button

var start_pos
var slide_pos
var slid_out = false
var sliding = false

var color_empty = Color(1, 1, 1, 0)
var color_white = Color(1, 1, 1, 0.4)
var color_red = Color(1, 0, 0, 0.4)
var color_green = Color(0, 1, 0, 0.4)

var main_script
var scan_link
var overlay
var settings_slider

var header = "Content-Type: application/json"

var choosing_sender_networks = false
var choosing_recipient_networks = false
var finalizing_choices = false

var confirming_choices = false

var previous_token_length = 0

var currently_selected_network
var selected_networks = []
var potential_sender_networks = []
var potential_recipient_networks = []


func _ready():
	main_script = get_parent()
	overlay = main_script.get_node("Overlay")
	settings_slider = main_script.get_node("Settings")
	start_pos = rect_position
	slide_pos = rect_position
	slide_pos.x += 353
	self.connect("pressed", self, "slide")
	$Confirm.connect("pressed", self, "confirm_choices")
	$AddNetwork.connect("pressed", self, "add_network")
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
	
	if $AddressEntry.text.length() != previous_token_length:
		$ScanLink.visible = false
		previous_token_length = $AddressEntry.text.length()
		if previous_token_length == 42 && $NetworkLabel.text != "":
			get_erc20_name($NetworkLabel.text, $AddressEntry.text)
			if choosing_sender_networks:
				get_erc20_balance($NetworkLabel.text, $AddressEntry.text)
		else:
			$TokenLabel.text = ""
	
	if sliding && !$SlideTween.is_active():
		sliding = false
		if slid_out:
			text = "Cancel"
			start_new()
		else:
			text = "New Test"
			clear_all()
		

func start_new():
	choosing_sender_networks = true
	$AddNetwork.visible = true
	currently_selected_network = ""
	potential_sender_networks = []
	potential_recipient_networks = []
	selected_networks = []

	
func pick_network(network):
	if choosing_sender_networks || choosing_recipient_networks:
		currently_selected_network = network
		wipe_buttons()
		get_button_overlay(network).color = color_green
		$NetworkLabel.text = network
		
		Ethers.perform_request(
		"eth_getBalance", 
		[Ethers.user_address, "latest"], 
		Network.network_info[network]["rpc"], 
		0, 
		self, 
		"load_network_gas", 
		{}
		)
		
		if choosing_sender_networks && potential_sender_networks != []:
			for potential_sender in potential_sender_networks:
				if potential_sender["network"] == network:
					var token_contract = potential_sender["token_contract"]
					$AddressEntry.text = token_contract
					get_erc20_name(network, token_contract)
					get_erc20_balance(network, token_contract)	

func add_network():
	var network = $NetworkLabel.text
	var token_name = $TokenLabel.text
	if network != "" && token_name != "" && $AddressEntry.text.length() == 42 && !network in selected_networks:
		if choosing_sender_networks:
			var potential_sender = {
				"network": network,
				"token_contract": token_name
			} 
			potential_sender_networks.append(potential_sender)
			clear_text()


func confirm_choices():
	if choosing_sender_networks:
		choosing_sender_networks = false
		choosing_recipient_networks = true
		currently_selected_network = ""
		selected_networks = []
		wipe_buttons()
		clear_text()
		$Prompt.text = "Choose recipient networks."
		
	elif choosing_recipient_networks:
		choosing_recipient_networks = false
		finalizing_choices = true
		currently_selected_network = ""
		selected_networks = []
		wipe_buttons()
		clear_text()
		$AddNetwork.visible = false
		$Prompt.text = "Name your test."
	elif finalizing_choices && $AddressEntry.text != "":
		var test_name = $AddressEntry.text
		var test = {
			"sender_networks": potential_sender_networks,
			"recipient_networks": potential_recipient_networks
		}
		main_script.save_test(test_name, test)
		slide()


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
	$Prompt.text = "Choose sender networks and\nprovide local token addresses.\nYou must have a balance to\nrun tests."
	var choosing_sender_networks = false
	var choosing_recipient_networks = false
	var finalizing_choices = false
	currently_selected_network = ""
	selected_networks = []
	potential_sender_networks = []
	potential_recipient_networks = []
	wipe_buttons()
	$AddNetwork.visible = true
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			button.get_node("Overlay").color = color_empty
			

func wipe_buttons():
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			if !button.name in selected_networks && button.name != currently_selected_network:
				button.get_node("Overlay").color = color_empty

func get_button_overlay(network):
	for button in $NetworkButtons.get_children():
		if button.name == network:
			return button.get_node("Overlay")

func highlight_button(network):
	if !network in selected_networks && network != currently_selected_network:
		if get_button_overlay(network).color == color_empty:
			get_button_overlay(network).color = color_white
		else:
			get_button_overlay(network).color = color_empty
	
func get_erc20_name(network, token_contract):
	var network_info = Network.network_info.duplicate()
	var chain_id = int(network_info[network]["chain_id"])
	var rpc = network_info[network]["rpc"]
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.get_token_name(content, chain_id, rpc, token_contract)
	
	Ethers.perform_request(
		"eth_call", 
		[{"to": token_contract, "input": calldata}, "latest"], 
		rpc, 
		0, 
		self, 
		"load_token_data", 
		{"function_name": "get_token_name", "token_contract": token_contract, "network": network}
		)
	
	
func get_erc20_balance(network, token_contract):
	var network_info = Network.network_info.duplicate()
	var chain_id = int(network_info[network]["chain_id"])
	var rpc = network_info[network]["rpc"]
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.check_token_balance(content, chain_id, rpc, token_contract)
	
	Ethers.perform_request(
		"eth_call", 
		[{"to": token_contract, "input": calldata}, "latest"], 
		rpc, 
		0, 
		self, 
		"load_token_data", 
		{"function_name": "check_token_balance", "token_contract": token_contract, "network": network}
		)


func load_network_gas(callback):
	if callback["success"]:
		var balance = String(callback["result"].hex_to_int())
		$GasBalance.text = "Balance: " + balance
		
	
func load_token_data(callback):
	if callback["success"]:
		var args = callback["callback_args"]
		if args["function_name"] == "get_token_name":
			if callback["result"] != "0x":
				$TokenLabel.text = FastCcipBot.decode_hex_string(callback["result"])
				var network_info = Network.network_info.duplicate()
				var network = args["network"]
				scan_link = Ethers.network_info[network]["scan_url"] + "address/" + $AddressEntry.text
				$ScanLink.visible = true
				
		if args["function_name"] == "check_token_balance":
			if callback["result"] != "0x":
				var balance = FastCcipBot.decode_u256(callback["result"])
				$TokenBalance.text = "Balance: " + balance
			else:
				$TokenBalance.text = ""
		else:
			$TokenBalance.text = ""

func open_scanner_link():
	OS.shell_open(scan_link)

func ethereum_request_failed(network, request_type, extra_args):
	pass
