extends ColorRect


var token
var main
var account
var active = false

var local_network
var local_token
var token_decimals

var gas_balance = "0"
var token_balance = "0"
var deposited_tokens = "0"
var total_liquidity = "0"

var maximum_gas_fee = "0.1"

var deposit_pending = false
var withdrawal_pending = false


func initialize(_main, _token, _account):
	main = _main
	token = _token.duplicate()
	account = _account
	local_network = token["local_network"]
	local_token = token["local_token"]
	token_decimals = token["token_decimals"]
	maximum_gas_fee = token["maximum_gas_fee"]
	
	main.initialize_network_balance(local_network, local_token)
	
	get_token_text()
	get_balances()
	
	$ToggleMonitoring.connect("pressed", toggle_monitoring)
	$ManageLane.connect("pressed", open_lane_manager)
	$DeleteCheck/No.connect("pressed", cancel_lane_deletion)
	$DeleteCheck/Yes.connect("pressed", confirm_lane_deletion)
	
	$Deposit.connect("pressed", approve_tokens)
	$Withdraw.connect("pressed", withdraw_tokens)
	$LaneManager/CheckPending.connect("pressed", check_for_manual_execution)
	$LaneManager/Back.connect("pressed", close_lane_manager)
	$LaneManager/Delete.connect("pressed", open_lane_deletion)
	$LaneManager/EditLaneConfig.connect("pressed", edit_token_lane)



func get_token_text():
	var token_text = "Serving " + token["token_name"] + "\non " + local_network + "\nMonitoring messages from:\n"
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

	Ethers.get_gas_balance(
			local_network, 
			account, 
			self, 
			"update_gas_balance"
			)
	
	Ethers.get_erc20_balance(
			local_network, 
			Ethers.get_address(account), 
			local_token,
			token_decimals,
			self, 
			"update_erc20_balance"
			)





func update_gas_balance(callback):
	if callback["success"]:
		gas_balance = callback["result"]
		main.account_balances[account][local_network]["gas"] = gas_balance
		$GasBalance.text = "Gas: " + gas_balance.left(6)
	else:
		main.print_message("Failed to retrieve gas balance on " + local_network)


func update_erc20_balance(callback):
	if callback["success"]:
		token_balance = callback["result"]
		main.account_balances[account][local_network][local_token]["balance"] = token_balance
		$TokenBalance.text = token["token_name"] + " Balance: " + token_balance
		
		var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
		var calldata = Ethers.get_calldata("READ", main.SCRYPOOL_ABI, "userStakedTokens", [Ethers.get_address(account), local_token])
		Ethers.read_from_contract(
						local_network,
						scrypool_contract,
						calldata,
						self,
						"update_deposited_tokens"
						)
	else:
		main.print_message("Failed to retrieve token balance on " + local_network)


func update_deposited_tokens(callback):
	if callback["success"]:
		deposited_tokens = callback["result"][0]
		main.account_balances[account][local_network][local_token]["deposited_balance"] = deposited_tokens
		$YourLiquidity.text = "Your Liquidity:\n " + Ethers.convert_to_smallnum(deposited_tokens, token_decimals)
		
		var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
		var calldata = Ethers.get_calldata("READ", main.SCRYPOOL_ABI, "availableLiquidity", [local_token])
		Ethers.read_from_contract(
						local_network,
						scrypool_contract,
						calldata,
						self,
						"update_total_liquidity"
						)
	
	
	else:
		main.print_message("Failed to retrieve deposited tokens on " + local_network)


func update_total_liquidity(callback):
	if callback["success"]:
		total_liquidity = callback["result"][0]
		main.account_balances[account][local_network][local_token]["total_liquidity"] = total_liquidity
		$ScryPoolLiquidity.text = "ScryPool Total Liquidity:\n " + Ethers.convert_to_smallnum(total_liquidity, token_decimals)


func toggle_monitoring():
	
	if active:
		active = false
		$ToggleMonitoring.text = "Start Monitoring"
		# DEBUG
		main.active_token_lanes.erase(self)
		return

	#NOTE
	# The lane will still become active even if it isn't ready,
	# it just won't be able to send transactions.
	
	# DEBUG
	# turned off for now
	#check_if_ready()
	
	active = true
	$ToggleMonitoring.text = "Stop Monitoring"
	# DEBUG
	main.active_token_lanes.push_back(self)
	
	# DEBUG
	# This could trigger a call to update the balances in main,
	# and check the available liquidity for the token on ScryPool


# DEBUG
# fix
func check_if_ready():
	if gas_balance == "0":
		main.print_message("Not enough gas on " + local_network)
		return false
	if deposited_tokens == "0":
		main.print_message("Deposit " + token["token_name"] + " using Manage Lane button")
		return false
	if float(gas_balance) < float(token["maximum_gas_fee"]):
		main.print_message(local_network + " gas below maximum gas fee")
		return false
	if float(deposited_tokens) < float(token["minimum_transfer"]):
		main.print_message("Deposit " + token["token_name"] + " using Manage Lane button")
		return false
	
	return true


func open_lane_manager():
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


func confirm_lane_deletion():
	main.application_manifest["monitored_tokens"].erase(token)
	main.save_application_manifest()
	main.load_token_lanes()


func cancel_lane_deletion():
	$DeleteCheck.visible = false


func approve_tokens():
	if token_balance == "0":
		main.print_message("Nothing to deposit")
		return
	if deposit_pending:
		main.print_message("Please wait for pending deposit")
		return
	
	deposit_pending = true
	
	if main.has_approval(local_network, local_token):
		deposit_tokens()
		return
		
	var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
	var params = [scrypool_contract, "MAX"]
	var callback_args = {"token_lane": self, "transaction_type": "Approve ScryPool", "approved_contract": local_token}

	Ethers.approve_erc20_allowance(
				account, 
				local_network, 
				local_token, 
				scrypool_contract, 
				"MAX", 
				self, 
				"handle_approval", 
				callback_args
				)


func deposit_tokens():
	deposit_pending = true
	
	var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
	var params = [local_token, Ethers.convert_to_bignum(token_balance, token_decimals)]
	var callback_args = {"token_lane": self, "transaction_type": "Deposit"}
	
	main.queue_transaction(
		account, 
		local_network, 
		scrypool_contract, 
		"depositTokens", 
		params, 
		callback_args,
		maximum_gas_fee
		)
	
	


func withdraw_tokens():
	if deposited_tokens == "0":
		main.print_message("Nothing to withdraw")
		return
	if withdrawal_pending:
		main.print_message("Please wait for pending withdrawal")
		return
	
	withdrawal_pending = true
	var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
	var params = [local_token]
	var callback_args = {"token_lane": self, "transaction_type": "Withdrawal"}
	
	main.queue_transaction(
		account, 
		local_network, 
		scrypool_contract, 
		"withdrawTokens", 
		params, 
		callback_args,
		maximum_gas_fee
		)
	
	

func check_for_manual_execution():
	main.print_message("Not yet implemented")
	

func claim_reward():
	pass


func pause():
	#if out of gas or tokens
	pass


func edit_token_lane():
	# DEBUG
	# Don't open if active is true
	var monitored_token_form = main._monitored_token_form.instantiate()
	monitored_token_form.main = main
	monitored_token_form.account = account
	main.add_child(monitored_token_form)
	
	#use the token to fill in all the fields of the form

func handle_approval(callback):
	if callback["success"]:
		var network = callback["network"]
		var approved_contract = callback["callback_args"]["approved_contract"]
		var transaction_type = callback["callback_args"]["transaction_type"]
		main.application_manifest["approvals"][network].push_back(approved_contract)
		main.save_application_manifest()
		
		match transaction_type:
			"Approve ScryPool": deposit_tokens()
