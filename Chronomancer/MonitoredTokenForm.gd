extends Control

@onready var input = $Form/Input

var main
var account

var previous_local_network = ""
var previous_local_token = ""
var minimum_transfer
var minimum_reward_percent
var maximum_gas_fee
var min_reward

var local_gas_balance = "0"
var local_token_info = []
var remote_tokens = {}


func _ready():
	$Form/Input/Confirm.connect("pressed", confirm)
	$Form/Input/Cancel.connect("pressed", cancel)
	$Form/ConfirmCancel/Yes.connect("confirm_cancel", cancel)
	$Form/ConfirmCancel/GoBack.connect("go_back", cancel)
	$Form/ConfirmAdd/Confirm.connect("confirm_add", cancel)
	$Form/ConfirmAdd/GoBack.connect("go_back", cancel)


func confirm():
	if !form_valid():
		return
	var monitored_token = get_monitored_token()
	var prompts = get_prompts(monitored_token)
	$Form/Input.visible = false
	$Form/ConfirmAdd.visible = true
	$Form/ConfirmAdd/Prompt.text = prompts[0]
	$Form/ConfirmAdd/MathPrompt.text = prompts[1]


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
	var monitored_token = get_monitored_token()
	
	main.application_manifest["monitored_tokens"].push_back(monitored_token)
	main.save_application_manifest()
	
	queue_free()


func get_monitored_token():
	var local_network = input.get_node("LocalNetwork").text
	var local_token = input.get_node("LocalToken").text
	var minimum_transfer = float(input.get_node("MinimumTransfer").text)
	var minimum_reward_percent = float(input.get_node("MinimumRewardPercent").text)
	var maximum_gas_fee = float(input.get_node("MaximumGasFee").text)
	
	
	var monitored_token = {
		"local_network": local_network,
		"local_token": local_token,
		"minimum_transfer": minimum_transfer,
		"minimum_reward_percent": minimum_reward_percent,
		"maximum_gas_fee": maximum_gas_fee,
		"remote_networks": {}
	}
	
	
	for network in input.get_node("RemoteNetworks").get_children():
		var network_name = network.get_node("RemoteNetwork").text
		var remote_token = network.get_node("RemoteToken").text
		
		if network_name != "" && remote_token != "":
			monitored_token["remote_networks"][network_name] = remote_token

	
	return monitored_token


func _process(delta):
	check_local_network()
	check_local_token()
	check_remote_tokens()
	calculate_worst_case()


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
		if local_token.begins_with("0x") && local_token.length() == 42: 
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
				if remote_token.begins_with("0x") && remote_token.length() == 42: 
					remote_tokens[remote_token] = ""
					Ethers.get_erc20_info(
							network_name, 
							Ethers.get_address(account), 
							remote_token, 
							self, 
							"update_remote_token_name",
							{"remote_token": remote_token}
							)


func update_remote_token_name(callback):
	if callback["success"]:
		var remote_token = callback["callback_args"]["remote_token"]
		remote_tokens[remote_token] = callback["result"][0]


func calculate_worst_case():
	minimum_transfer = input.get_node("MinimumTransfer").text
	minimum_reward_percent = input.get_node("MinimumRewardPercent").text
	maximum_gas_fee = input.get_node("MaximumGasFee").text
	
	if minimum_transfer && minimum_reward_percent && maximum_gas_fee:
		min_reward = float(minimum_transfer) * float(minimum_reward_percent)
		input.get_node("WorstCase").visible = true
		input.get_node("WorstCase").text = "Worst Case: " + maximum_gas_fee + " Gas for " + str(min_reward) + " Tokens"
	else:
		input.get_node("WorstCase").visible = false
	

func form_valid():
	
	if !previous_local_network in Ethers.network_info.keys():
		show_error("Local network not found in network info")
		return false
	
	if local_token_info == []:
		show_error("Local token not provided")
		return false
	
	if previous_local_token.begins_with("0x") && previous_local_token.length() == 42:
		pass
	else:
		show_error("Invalid local token")
		return false
	
	if minimum_transfer && minimum_reward_percent && maximum_gas_fee:
		pass
	else:
		show_error("Invalid minimums or maximums")
		return false
	
	#DEBUG
	# These checks are more appropriate when the account actually
	# attempts to monitor incoming messages.
	
	#if float(local_gas_balance) < float(maximum_gas_fee):
		#show_error("Insufficient gas on local network")
		#return false
	#if local_token_info[2] < float(minimum_transfer):
		#show_error("Insufficient local token balance")
		#return false
	
	var token_name = local_token_info[0]
	var no_remote_networks = true
	
	for network in input.get_node("RemoteNetworks").get_children():
		var remote_network_name = network.get_node("RemoteNetwork").text
		var remote_token = network.get_node("RemoteToken").text
		
		if remote_network_name != "" && remote_token != "":
			
			no_remote_networks = false
			
			if !remote_network_name in Ethers.network_info.keys():
				show_error(remote_network_name + " not found in network info")
				return false
			
			if !remote_network_name in Ethers.network_info[previous_local_network]["onramp_contracts"]:
				show_error(remote_network_name + "OnRamp not found for local network")
				return false
			
			if !remote_token in remote_tokens.keys():
				show_error("Invalid token address for " + remote_network_name)
				return false
			
			if remote_tokens[remote_token] != token_name:
				show_error("Mismatched token '" + remote_token + "' on " + remote_network_name)
				return false
	
	if no_remote_networks:
		show_error("Define at least 1 remote network")
		return false
	
	return true
	


func show_error(error):
	$Form/Input/Error.text = error
	$Form/Input/Error.modulate.a = 1
	var fadeout = create_tween()
	fadeout.tween_property($Form/Input/Error,"modulate:a", 0, 3.5).set_trans(Tween.TRANS_LINEAR)
	fadeout.play()


func get_prompts(monitored_token):
	var prompt = "You will provide fast transfers for\n" + local_token_info[0] + "\non " + previous_local_network + "\nmonitoring incoming messages from the following networks:\n\n"
	
	for network in monitored_token["remote_networks"].keys():
		prompt += network + "\n"
	
	var math_prompt = "The minimum transfer amount is " + str(minimum_transfer) + ".\nThe minimum reward percentage is " + str(minimum_reward_percent) + ".\nThe maximum gas fee per transfer is " + str(maximum_gas_fee) + ".\n\nIn the worst case, you will spend " + str(maximum_gas_fee) + " gas\nto receive " + str(min_reward) + " tokens as a reward."
	
	return [prompt, math_prompt]
