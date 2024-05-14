extends Control

var glow = preload("res://Glow.tscn")
var transaction_lane = preload("res://TransactionLane.tscn")

var transaction_lanes = []
var targets = []

func _ready():
	check_keystore()
	Ethers.get_address()
	check_network_info()
	check_saved_tests()
	show_test_names()
	
	$StartTest.connect("pressed", self, "toggle_testing")

func check_keystore():
	var file = File.new()
	if file.file_exists("user://keystore") != true:
		var MbedTLS = Crypto.new()
		var key = MbedTLS.generate_random_bytes(32)
		file.open("user://keystore", File.WRITE)
		file.store_buffer(key)
		file.close()

func check_network_info():
	var file = File.new()
	if file.file_exists("user://network_info") != true:
		Network.network_info = Network.default_network_info.duplicate()
		file.open("user://network_info", File.WRITE)
		file.store_string(JSON.print(Network.network_info))
		file.close()
	else:
		file.open("user://network_info", File.READ)
		var loaded_network_info = parse_json(file.get_as_text())
		Network.network_info = loaded_network_info

func check_saved_tests():
	var file = File.new()
	if file.file_exists("user://saved_tests") != true:
		var content = {" Demo Test ": bnm_test.duplicate(), "Mini Test": mini_bnm_test.duplicate()}
		file.open("user://saved_tests", File.WRITE)
		file.store_string(JSON.print(content))
		file.close()

func save_test(test_name, test):
	var file = File.new()
	file.open("user://saved_tests", File.READ)
	var content = parse_json(file.get_as_text())
	content[test_name] = test
	file.close()
	file.open("user://saved_tests", File.WRITE)
	file.store_string(JSON.print(content))
	file.close()
	load_test(test)

func show_test_names():
	for node in $SavedTestsList/SavedTestsScroll/SavedTestsContainer.get_children():
		node.queue_free()
	$SavedTestsList/SavedTestsScroll/SavedTestsContainer.rect_min_size.y = 0
	var file = File.new()
	file.open("user://saved_tests", File.READ)
	var content = parse_json(file.get_as_text())
	file.close()
	
	var button_spacer = 3
	for name in content.keys():
		var new_button = Button.new()
		new_button.text = name
		new_button.mouse_default_cursor_shape = 2
		new_button.connect("pressed", self, "load_test", [name])
		$SavedTestsList/SavedTestsScroll/SavedTestsContainer.add_child(new_button)
		new_button.rect_position.x += 3
		new_button.rect_position.y += button_spacer
		button_spacer += 26
		$SavedTestsList/SavedTestsScroll/SavedTestsContainer.rect_min_size.y += 26
	
func load_test(test_name):
	$StartTest.visible = false
	transaction_lanes = []
	targets = []
	for node in $Senders.get_children():
		node.queue_free()
	for node in $Recipients.get_children():
		node.queue_free()
	var file = File.new()
	file.open("user://saved_tests", File.READ)
	var content = parse_json(file.get_as_text())
	var y_spacer = 0
	
	if test_name in content.keys():
		var test = content[test_name]
		
		if test["recipient_networks"].empty():
			print("invalid test case")
			return
			
		$StartTest.visible = true
		
		for network in test["sender_networks"].keys():
			var new_transaction_lane = transaction_lane.instance()
			transaction_lanes.append(new_transaction_lane)
			$Senders.add_child(new_transaction_lane)
			new_transaction_lane.get_node("TransactionSender").recipients = test["recipient_networks"].duplicate()
			new_transaction_lane.get_node("TransactionSender").initialize(self, network, test["sender_networks"][network])
			new_transaction_lane.rect_position.y += y_spacer
			
			y_spacer += 120
		
		y_spacer = 0
		for network in test["recipient_networks"]:
			var new_target = TextureRect.new()
			new_target.texture = load(Network.network_info[network]["logo"])
			$Recipients.add_child(new_target)
			new_target.rect_position.y += y_spacer
			targets.append({
				"network": network,
				"rect_position": new_target.rect_global_position
			})
			y_spacer += 120

func toggle_testing():
	if $StartTest.text == "Start Test":
		$StartTest.text = "Stop Test"
	else:
		$StartTest.text = "Start Test"
	for _lane in transaction_lanes:
		var lane = _lane.get_node("TransactionSender")
		if lane.active == true:
			lane.active = false
		else:
			lane.active = true
			lane.check_for_entrypoint_allowance()



var bnm_test =  {
	"sender_networks": {
		"Ethereum Sepolia": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
		"Arbitrum Sepolia": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"Optimism Sepolia": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
		"Base Sepolia": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e"
	},
	"recipient_networks": ["Ethereum Sepolia", "Arbitrum Sepolia", "Optimism Sepolia", "Base Sepolia"]
}

var mini_bnm_test =  {
	"sender_networks": {
		"Arbitrum Sepolia": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"Base Sepolia": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e"
	},
	"recipient_networks": ["Arbitrum Sepolia", "Base Sepolia"]
}
