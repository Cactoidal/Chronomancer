extends Button

var eth_http_request = preload("res://EthRequest.tscn")

var start_pos
var slide_pos
var slid_out = false
var sliding = false

var color_empty = Color(1, 1, 1, 0)
var color_white = Color(1, 1, 1, 0.4)
var color_red = Color(1, 0, 0, 0.4)
var color_green = Color(0, 1, 0, 0.4)

var main_script
var network_info
var http 
var scan_link

var header = "Content-Type: application/json"

var choosing_service_network = false
var choosing_monitored_networks = false
var choosing_minimum = false
var confirming_choices = false

var previous_token_length = 0

var new_token = {
		"serviced_network": "",
		"local_token_contract ": "",
		"monitored_networks": {
		 #network : remote_token_contract
		},
		"endpoint_contract":"",
		"minimum_transfer": 0
}

var pending_token = {}

func _ready():
	main_script = get_parent()
	network_info = main_script.network_info
	http = main_script.get_node("HTTP")
	start_pos = rect_position
	slide_pos = rect_position
	slide_pos.x += 355
	pending_token = new_token
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
		slid_out = true
		sliding = true
		$SlideTween.interpolate_property(self, "rect_position", start_pos, slide_pos, 1, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$SlideTween.start()
	elif slid_out && !sliding:
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
		else:
			$TokenLabel.text = ""
	
	if sliding && !$SlideTween.is_active():
		sliding = false
		if slid_out:
			text = "Cancel"
			start_new()
		else:
			text = "Add Token"
			clear_all()
		

func start_new():
	pending_token = {"serviced_network":"", "monitored_networks": {}}
	choosing_service_network = true

func pick_network(network):
	if choosing_service_network:
		pending_token["serviced_network"] = network
		get_button_overlay(network).color = color_red
		wipe_buttons()
		clear_text()
		$NetworkLabel.text = network
	elif choosing_monitored_networks && network != pending_token["serviced_network"]:
		wipe_buttons()
		clear_text()
		get_button_overlay(network).color = color_green
		$NetworkLabel.text = network
		if network in pending_token["monitored_networks"].keys():
			$AddressEntry.text = pending_token["monitored_networks"][network]
			get_erc20_name(network, $AddressEntry.text)


func confirm_choices():
	if choosing_service_network:
		if pending_token["serviced_network"] != "" && $TokenLabel.text != "" && $AddressEntry.text.length() == 42:
			clear_text()
			choosing_service_network = false
			choosing_monitored_networks = true
			$Prompt.text = "Provide remote token addresses\nfor each network to monitor."
			$AddNetwork.visible = true
	if choosing_monitored_networks == true && !pending_token["monitored_networks"].keys().empty():
		clear_text()
		$AddNetwork.visible = false
		choosing_minimum = true
		choosing_monitored_networks = false
		$Prompt.text = "Set the transfer minimum."
	if choosing_minimum && $AddressEntry.text.is_valid_float():
		pending_token["minimum"] = int($AddressEntry.text)
		clear_text()
		$AddressEntry.visible = false
		$Prompt.text = ""
		var network_list_string = ""
		for network in pending_token["monitored_networks"].keys():
			network_list_string += network + "\n"
		$FinalConfirm.text = "You will provide fast transfers to " + pending_token["serviced_network"] + ",\nby monitoring incoming traffic from:\n\n" + network_list_string + "\nAnd will only serve transactions with a \nminimum transfer of " + String(pending_token["minimum"]) + " tokens."
		choosing_minimum = false
		confirming_choices = true


func add_monitored_network():
	var network = $NetworkLabel.text
	var token_name = $TokenLabel.text
	if network != "" && token_name != "" && $AddressEntry.text.length() == 42:
		pending_token["monitored_networks"][network] = $AddressEntry.text
		clear_text()

func clear_text():
	previous_token_length = 0
	$TokenLabel.text = ""
	$NetworkLabel.text = ""
	$AddressEntry.text = ""
	$ScanLink.visible = false
	$FinalConfirm.text = ""
	
func clear_all():
	clear_text()
	$AddNetwork.visible = false
	$Prompt.text = "Choose a network to serve and\nprovide your token's local address.\nYou must have a balance to perform\nfast transfers."
	choosing_service_network = false
	choosing_monitored_networks = false
	choosing_minimum = false
	confirming_choices = false
	pending_token = new_token
	wipe_buttons()
	$AddressEntry.visible = true

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
		elif get_button_overlay(network).color != color_green:
			get_button_overlay(network).color = color_empty
	
func get_erc20_name(network, token_contract):
	var chain_id = network_info[network]["chain_id"]
	var rpc = network_info[network]["rpc"]
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = FastCcipBot.get_token_name(content, chain_id, rpc, token_contract)
	perform_ethereum_request(network, "eth_call", [{"to": token_contract, "input": calldata}, "latest"], {"function_name": "check_token_balance", "token_contract": token_contract})

func perform_ethereum_request(network, method, params, extra_args={}):
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
		"eth_call": load_token_name(network, get_result, extra_args)

func load_token_name(network, get_result, extra_args):
	if "result" in get_result.keys():
		if get_result["result"] != "0x":
			$TokenLabel.text = FastCcipBot.decode_hex_string(get_result["result"])
			scan_link = network_info[network]["scan_url"] + "address/" + $AddressEntry.text
			$ScanLink.visible = true

func open_scanner_link():
	OS.shell_open(scan_link)
