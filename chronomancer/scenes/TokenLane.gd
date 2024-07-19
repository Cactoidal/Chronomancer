extends ColorRect


var token
var main
var account
var active = false

var gas_balance = "0"
var token_balance = "0"
var deposited_tokens = "0"

var deposit_pending = false
var withdrawal_pending = false

func initialize(_main, _token, _account):
	main = _main
	token = _token.duplicate()
	account = _account
	
	get_token_text()
	get_balances()
	
	$ToggleMonitoring.connect("pressed", toggle_monitoring)
	$ManageLane.connect("pressed", open_lane_manager)
	$DeleteCheck/No.connect("pressed", cancel_lane_deletion)
	$DeleteCheck/Yes.connect("pressed", confirm_lane_deletion)
	
	$LaneManager/Deposit.connect("pressed", deposit_tokens)
	$LaneManager/Withdraw.connect("pressed", withdraw_tokens)
	$LaneManager/CheckPending.connect("pressed", check_for_manual_execution)
	$LaneManager/Back.connect("pressed", close_lane_manager)
	$LaneManager/Delete.connect("pressed", open_lane_deletion)



func get_token_text():
	var token_text = "Serving " + token["token_name"] + "\non " + token["local_network" + "\nMonitoring messages from:\n"]
	var token_text2 = ""
	var remote_networks = token["remote_networks"].keys()
	var index = 0
	for network in remote_networks:
		if index < 5:
			token_text += network + "\n"
		else:
			token_text2 += network + "\n"
		index += 1
	
	$TokenText.text = token_text
	$TokenText2.text = token_text2


func get_balances():
	var network = token["local_network"]
	Ethers.get_gas_balance(
			network, 
			account, 
			self, 
			"update_gas_balance"
			)
	
	Ethers.get_erc20_balance(
			network, 
			Ethers.get_address(account), 
			token["local_token"],
			token["token_decimals"],
			self, 
			"update_erc20_balance"
			)


func update_gas_balance(callback):
	if callback["success"]:
		gas_balance = callback["result"]
		$GasBalance.text = "Gas: " + gas_balance.left(6)
		$LaneManager/GasBalance.text = "Gas Balance: " + gas_balance.left(6)
	else:
		main.print_message("Failed to retrieve gas balance on " + token["local_network"])

func update_erc20_balance(callback):
	if callback["success"]:
		token_balance = callback["result"]
		$LaneManager/TokenBalance.text = token["token_name"] + " Balance: " + token_balance.left(6)
		
		var calldata = Ethers.get_calldata("READ", main.SCRYPOOL_ABI, "userStakedTokens", [Ethers.get_address(account), token["local_token"]])
		Ethers.read_from_contract(
						token["local_network"],
						token["local_token"],
						calldata,
						self,
						"update_deposited_tokens"
						)
	else:
		main.print_message("Failed to retrieve token balance on " + token["local_network"])


func update_deposited_tokens(callback):
	if callback["success"]:
		deposited_tokens = callback["result"][0]
		$LaneManager/TokenBalance.text = "Tokens: " + deposited_tokens.left(6)
	
	else:
		main.print_message("Failed to retrieve deposited tokens on " + token["local_network"])


func new_monitored_token_form():
	var monitored_token_form = main._monitored_token_form.instantiate()
	monitored_token_form.main = self
	monitored_token_form.account = account
	main.add_child(monitored_token_form)


func toggle_monitoring(token):
	
	if active:
		active = false
		$ToggleMonitoring.text = "Start Monitoring"
		return

	if gas_balance == "0":
		main.print_message("Not enough gas on " + token["local_network"])
		return
	if deposited_tokens == "0":
		main.print_message("Deposit tokens using Manage Lane button")
		return
	
	# DEBUG
	# check for anything else that would preclude becoming active,
	# like having fewer tokens than the minimum transfer
	
	active = true
	$ToggleMonitoring.text = "Stop Monitoring"
	


func open_lane_manager(token):
	$LaneManager.visible = true


func close_lane_manager():
	$LaneManager.visible = false


func open_lane_deletion():	
	if active:
		main.print_message("Cannot delete active lane")
		return
	if deposited_tokens != "0":
		main.print_message("Cannot delete lane with deposited tokens")
		return
	
	#DEBUG
	# also can't delete if you have unclaimed rewards
		
	$DeleteCheck.visible = true


func confirm_lane_deletion(token):
	#DEBUG
	main.application_manifest["monitored_tokens"].erase(token)
	main.save_application_manifest()
	main.load_token_lanes()


func cancel_lane_deletion():
	$DeleteCheck.visible = false


func deposit_tokens():
	if token_balance == "0":
		main.print_message("Nothing to deposit")
		return
	if deposit_pending:
		main.print_message("Please wait for pending deposit")
		return
	
	deposit_pending = true
	var params = [token["local_token"], Ethers.convert_to_bignum(token_balance)]
	
	queue_transaction("depositTokens", params, "Deposit")
	
	


func withdraw_tokens():
	if deposited_tokens == "0":
		main.print_message("Nothing to withdraw")
		return
	if withdrawal_pending:
		main.print_message("Please wait for pending withdrawal")
		return
	
	withdrawal_pending = true
	var params = [token["local_token"]]
	
	queue_transaction("withdrawTokens", params, "Withdrawal")
	

func check_for_manual_execution():
	main.print_message("Not yet implemented")
	

func claim_reward():
	pass


func pause():
	#if out of gas or tokens
	pass


func queue_transaction(function_name, params, tx_type):
	var calldata = Ethers.get_calldata(
				"WRITE", 
				main.SCRYPOOL_ABI, 
				function_name, 
				params
				)
	
	var transaction = {
		"network": token["local_network"],
		"contract": token["local_token"],
		"calldata": calldata,
		"callback_args": {"token_lane": self, "tx_type": tx_type}
	}
	
	main.transaction_queue[account].push_back(transaction)


func deposit_complete():
	deposit_pending = false


func withdrawal_complete():
	withdrawal_pending = false
