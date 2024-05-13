extends Button

var start_pos
var slide_pos
var slid_out = false
var sliding = false

var network_info

var color_empty = Color(1, 1, 1, 0)
var color_white = Color(1, 1, 1, 0.4)
var color_red = Color(1, 0, 0, 0.4)
var color_green = Color(0, 1, 0, 0.4)

var main_script
var overlay
var add_token_slider

var picked_network

var new_token = {
		"serviced_network": "",
		"local_token_contract": "",
		"token_name": "",
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
	add_token_slider = main_script.get_node("AddToken")
	start_pos = rect_position
	slide_pos = rect_position
	slide_pos.x -= 357
	pending_token = new_token.duplicate()
	self.connect("pressed", self, "slide")
	$NetworkInfo/Network/Save.connect("pressed", self, "save_changes")
	$NetworkInfo/Network/RestoreDefaults.connect("pressed", self, "restore_network_defaults")
	$NetworkInfo/Network/ScanLink/ScanLink.connect("pressed", self, "open_scanner_link")
	$NetworkInfo/Chainlink/ChangePassword.connect("pressed", self, "change_password")
	$NetworkInfo/Chainlink/ShowKey.connect("pressed", self, "export_key")
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			button.connect("pressed", self, "pick_network", [button.name])
			button.connect("mouse_entered", self, "highlight_button", [button.name])
			button.connect("mouse_exited", self, "dehighlight_button", [button.name])

func slide():
	if !slid_out && !sliding:
		start_new()
		overlay.visible = true
		slid_out = true
		sliding = true
		$SlideTween.interpolate_property(self, "rect_position", start_pos, slide_pos, 1, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$SlideTween.start()
	elif slid_out && !sliding:
		if !add_token_slider.slid_out:
			overlay.visible = false
		slid_out = false
		sliding = true
		$SlideTween.interpolate_property(self, "rect_position", slide_pos, start_pos, 1, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$SlideTween.start()

func _process(delta):
		
	if sliding && !$SlideTween.is_active():
		sliding = false
		if slid_out:
			text = "Close"
			start_new()
		else:
			text = "Settings"


func start_new():
	network_info = Network.network_info.duplicate()
	pick_network("Chainlink")

func pick_network(network):
	picked_network = network
	wipe_buttons()
	get_button_overlay(network).color = color_green
	if network == "Chainlink":
		clear_text()
		$NetworkInfo/Chainlink.visible = true
		$NetworkInfo/Network.visible = false
		
	else:
		load_network_info(network)
		$NetworkInfo/Network.visible = true
		$NetworkInfo/Chainlink.visible = false

func clear_text():
	$NetworkInfo/Chainlink/Address.text = Ethers.user_address
	$NetworkInfo/Chainlink/PrivateKey.text = ""
	$NetworkInfo/Chainlink/Password.text = ""
	$NetworkInfo/Chainlink/OldPassword.text = ""
	$NetworkInfo/Chainlink/NewPassword.text = ""

func load_network_info(network):
	$NetworkInfo/Network/Network.text = network
	$NetworkInfo/Network/RPC.text = network_info[network]["rpc"]
	$NetworkInfo/Network/GasFee.text = network_info[network]["maximum_gas_fee"]
	$NetworkInfo/Network/Endpoint.text = network_info[network]["endpoint_contract"]

func save_changes():
	var network = picked_network
	network_info[network]["rpc"] = $NetworkInfo/Network/RPC.text
	network_info[network]["maximum_gas_fee"] = $NetworkInfo/Network/GasFee.text
	network_info[network]["endpoint_contract"] = $NetworkInfo/Network/Endpoint.text
	Network.network_info = network_info.duplicate()
	var file = File.new()
	file.open("user://network_info", File.WRITE)
	file.store_string(JSON.print(network_info.duplicate()))
	file.close()
	

func restore_network_defaults():
	var network = picked_network
	var default_network_info = Network.default_network_info.duplicate()
	$NetworkInfo/Network/RPC.text = default_network_info[network]["rpc"]
	$NetworkInfo/Network/GasFee.text = default_network_info[network]["maximum_gas_fee"]
	$NetworkInfo/Network/Endpoint.text = default_network_info[network]["endpoint_contract"]
	
func change_password():
	var file = File.new()
	var password = $NetworkInfo/Chainlink/OldPassword.text
	var new_password =  $NetworkInfo/Chainlink/NewPassword.text
	var error = file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
	var key = file.get_buffer(32)
	file.close()
	if error == 0 && new_password.length() > 0:
		file.open_encrypted_with_pass("user://encrypted_keystore", File.WRITE, new_password)
		file.store_buffer(key)
		file.close()
		Ethers.password = new_password
		$NetworkInfo/Chainlink/OldPassword.text = ""
		$NetworkInfo/Chainlink/NewPassword.text = ""
	

func export_key():
	var file = File.new()
	var password = $NetworkInfo/Chainlink/Password.text
	var error = file.open_encrypted_with_pass("user://encrypted_keystore", File.READ, password)
	if error == 0:
		var key = file.get_buffer(32)
		$NetworkInfo/Chainlink/PrivateKey.text = key.hex_encode()
	file.close()

func wipe_buttons():
	for button in $NetworkButtons.get_children():
		if button.name != "Frames":
			button.get_node("Overlay").color = color_empty

func get_button_overlay(network):
	for button in $NetworkButtons.get_children():
		if button.name == network:
			return button.get_node("Overlay")

func highlight_button(network):
	if network != picked_network:
		get_button_overlay(network).color = color_white

func dehighlight_button(network):
	if network != picked_network:
		get_button_overlay(network).color = color_empty

func open_scanner_link():
	var scan_link = network_info[picked_network]["scan_url"] + "address/" +  $NetworkInfo/Network/Endpoint.text
	OS.shell_open(scan_link)

func ethereum_request_failed(network, request_type, extra_args):
	pass
