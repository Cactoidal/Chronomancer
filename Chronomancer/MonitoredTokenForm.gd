extends Control

@onready var input = $Form/Input
#@onready var regex = RegEx.new()
var main
var account

func _ready():
	#regex.compile("^[0-9.]*$")
	$Form/Input/Confirm.connect("pressed", confirm)
	$Form/Input/Cancel.connect("pressed", cancel)
	$Form/ConfirmCancel/Yes.connect("confirm_cancel", cancel)
	$Form/ConfirmCancel/GoBack.connect("go_back", cancel)
	$Form/ConfirmAdd/Confirm.connect("confirm_add", cancel)
	$Form/ConfirmAdd/GoBack.connect("go_back", cancel)


func confirm():
	$Form/Input.visible = false
	$Form/ConfirmAdd.visible = true
	# change text


func cancel():
	$Form/Input.visible = false
	$Form/ConfirmCancel.visible = true


func go_back():
	$Form/Input.visible = true
	$Form/ConfirmCancel.visible = false
	$Form/ConfirmAdd.visible = false


func confirm_cancel():
	queue_free()


func confirm_add():
	var local_network = input.get_node("LocalNetwork").text
	var local_token = input.get_node("LocalToken").text
	var minimum_transfer = input.get_node("MinimumTransfer").text
	var minimum_reward_percent = input.get_node("MinimumRewardPercent").text
	var maximum_gas_fee = input.get_node("MaximumGasFee").text
	var remote_networks = []
	for network in input.get_node("RemoteNetworks").get_children():
		var network_name = network.get_node("RemoteNetwork").text
		var remote_token = network.get_node("RemoteToken").text
		
		if network_name != "" && remote_token != "":
			
			var remote_network = {
				"remote_network": network_name,
				"remote_token": remote_token
			}
			
			remote_networks.push_back(remote_network)
	
	var monitored_token = {
		"local_network": local_network,
		"local_token": local_token,
		"minimum_transfer": minimum_transfer,
		"minimum_reward_percent": minimum_reward_percent,
		"maximum_gas_fee": maximum_gas_fee,
		"remote_networks": remote_networks
	}
	
	var account = main.selected_account
	
	var path = "user://"
	
	
	queue_free()



func _process(delta):
	check_local_network()
	check_local_token()
	check_remote_tokens()
	calculate_worst_case()



var previous_local_network
var previous_local_token
var minimum_transfer
var minimum_reward_percent
var maximum_gas_fee

var local_gas_balance = "0"
var local_token_info = []
var remote_tokens = {}

func check_local_network():
	var local_network = input.get_node("LocalNetwork").text
	if local_network != previous_local_network:
		previous_local_network = local_network
		input.get_node("GasBalanceLabel").visible = false
		local_gas_balance = "0"
		if local_network in Ethers.network_info.keys():
			Ethers.get_gas_balance(local_network, account, self, "update_network_gas_balance")


func update_network_gas_balance(callback):
	input.get_node("GasBalanceLabel").visible = true
	if callback["success"]:
		local_gas_balance = callback["result"]
		input.get_node("GasBalanceLabel").text = "Gas Balance: " + local_gas_balance
	else:
		input.get_node("GasBalanceLabel").text = "Failed to retrieve Gas Balance"


func check_local_token():
	var local_token = input.get_node("LocalToken").text
	if local_token != previous_local_token:
		previous_local_token = local_token
		input.get_node("TokenBalanceLabel").visible = false
		local_token_info = []
		if local_token.begins_with("0x") && local_token.length == 42: 
			if previous_local_network in Ethers.network_info.keys():
				Ethers.get_erc20_info(
						previous_local_network, 
						Ethers.get_address(account), 
						local_token, 
						self, 
						"update_local_token_info"
						)


func update_local_token_info(callback):
	input.get_node("TokenBalanceLabel").visible = true
	if callback["success"]:
		local_token_info = callback["result"]
		#[name, str(decimals), balance]
		var token_name = local_token_info[0]
		var token_balance = local_token_info[2]
		input.get_node("TokenBalanceLabel").text = token_name + " Balance: " + token_balance
	else:
		input.get_node("TokenBalanceLabel").text = "Failed to retrieve Token Info"


func check_remote_tokens():
	for network in input.get_node("RemoteNetworks").get_children():
		var network_name = network.get_node("RemoteNetwork").text
		var remote_token = network.get_node("RemoteToken").text
		
		if network_name != "" && remote_token != "":
			if network_name in Ethers.network_info.keys():
				if remote_token.begins_with("0x") && remote_token.length == 42: 
					remote_tokens[remote_token] = ""
					Ethers.get_erc20_info(
							network_name, 
							Ethers.get_address(account), 
							remote_token, 
							self, 
							"update_remote_token_name"
							)


func update_remote_token_name():
	pass


func calculate_worst_case():
	minimum_transfer = input.get_node("MinimumTransfer").text
	minimum_reward_percent = input.get_node("MinimumRewardPercent").text
	maximum_gas_fee = input.get_node("MaximumGasFee").text
	
	if minimum_transfer && minimum_reward_percent && maximum_gas_fee:
		# DEBUG
		var min_reward = float(minimum_transfer) * float(minimum_reward_percent)
		input.get_node("WorstCase").visible = true
		input.get_node("WorstCase").text = "Worst Case: " + maximum_gas_fee + " Gas for " + str(min_reward) + " Tokens"
	else:
		input.get_node("WorstCase").visible = false
	

func check_form_validity():
	pass


func show_error(error):
	$Form/Input/Error.text = error
	$Form/Input/Error.modulate.a = 1
	#var fadeout = create_tween()
	#fadeout.tween_property($Form/Input/Error,"modulate:a", 0, 3.5).set_trans(Tween.TRANS_LINEAR)
	#fadeout.play()
