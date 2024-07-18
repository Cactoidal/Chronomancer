extends Control

var main
@onready var input = $Form/Input

func _ready():
	
	input.get_node("SaveChanges").connect("pressed", save_changes)
	input.get_node("RestoreDefaults").connect("pressed", restore_defaults)
	input.get_node("Cancel").connect("pressed", cancel)
	
	$Form/NetworkList/Close.connect("pressed", close)
	for network_button in $Form/NetworkList/Networks.get_children():
		network_button.connect("pressed", open_network_config.bind(network_button.name))



func open_network_config(network):
	$Form/NetworkList.visible = false
	input.visible = true
	
	for rpc in input.get_node("RPCs").get_children():
		rpc.text = ""
	
	input.get_node("NetworkName").text = network
	var network_info = Ethers.network_info[network].duplicate()
	
	if "chronomancer_endpoint" in network_info.keys():
		input.get_node("LocalChronomancer").text = network_info["chronomancer_endpoint"]
	
	if "scrypool_contract" in network_info.keys():
		input.get_node("LocalScryPool").text = network_info["scrypool_contract"]
	
	if "scan_url" in network_info.keys():
		input.get_node("ScanURL").text = network_info["scan_url"]
	
	if "bnm_contract" in network_info.keys():
		input.get_node("LocalBnM").text = network_info["bnm_contract"]
	
	var index = 0
	for rpc in network_info["rpcs"]:
		input.get_node("RPCs").get_children()[index].text = rpc
		index += 1


func save_changes():
	var rpcs = []
	for rpc in input.get_node("RPCs").get_children():
		if rpc.text:
			if rpc.text != "":
				rpcs.push_back(rpc.text)
	
	if rpcs.is_empty():
		show_error("Need at least 1 RPC URL")
		return

	var network = input.get_node("NetworkName").text
	var chronomancer_endpoint = input.get_node("LocalChronomancer").text
	var scrypool_contract = input.get_node("LocalScryPool").text
	var scan_url = input.get_node("ScanURL").text
	var bnm_contract = input.get_node("LocalBnM").text
	
	if is_valid_address(chronomancer_endpoint):
		Ethers.network_info[network]["chronomancer_endpoint"] = chronomancer_endpoint
	
	if is_valid_address(scrypool_contract):
		Ethers.network_info[network]["scrypool_contract"] = scrypool_contract
	
	if is_valid_address(bnm_contract):
		Ethers.network_info[network]["bnm_contract"] = bnm_contract
	
	if scan_url:
		if scan_url != "":
			Ethers.network_info[network]["scan_url"] = scan_url
	
	Ethers.network_info[network]["rpcs"] = rpcs
	
	var json = JSON.new()
	var file = FileAccess.open("user://ccip_network_info", FileAccess.WRITE)
	file.store_string(json.stringify(Ethers.network_info.duplicate()))
	file.close()
	
	input.visible = false
	$Form/NetworkList.visible = true
	


func cancel():
	input.visible = false
	$Form/NetworkList.visible = true


func close():
	queue_free()


func restore_defaults():
	var network = input.get_node("NetworkName").text
	var network_info = main.default_ccip_network_info[network].duplicate()
	
	if "chronomancer_endpoint" in network_info.keys():
		input.get_node("LocalChronomancer").text = network_info["chronomancer_endpoint"]
	else:
		input.get_node("LocalChronomancer").text = ""
	
	if "scrypool_contract" in network_info.keys():
		input.get_node("LocalScryPool").text = network_info["scrypool_contract"]
	else:
		input.get_node("LocalScryPool").text = ""
	
	if "scan_url" in network_info.keys():
		input.get_node("ScanURL").text = network_info["scan_url"]
	else:
		input.get_node("ScanURL").text = ""
	
	if "bnm_contract" in network_info.keys():
		input.get_node("LocalBnM").text = network_info["bnm_contract"]
	else:
		input.get_node("LocalBnM").text = ""
	
	var index = 0
	for rpc in input.get_node("RPCs").get_children():
		if index < network_info["rpcs"].size():
			rpc.text = network_info["rpcs"][index]
			index += 1
		else:
			rpc.text = ""


func show_error(error):
	$Form/Input/Error.text = error
	$Form/Input/Error.modulate.a = 1
	var fadeout = create_tween()
	fadeout.tween_property($Form/Input/Error,"modulate:a", 0, 3.5).set_trans(Tween.TRANS_LINEAR)
	fadeout.play()
	

func is_valid_address(address):
	#Address must be a string
	if typeof(address) == 4:
		if address.begins_with("0x") && address.length() == 42:
			if address.trim_prefix("0x").is_valid_hex_number():
				return true
	return false
