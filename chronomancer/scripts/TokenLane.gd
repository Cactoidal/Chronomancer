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
	$LaneManager/CheckPending.connect("pressed", check_pending_rewards)
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
		var network = callback["network"]
		#var gas_symbol = Ethers.network_info[network]["gas_symbol"]
		
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
	if main.lane_is_active():	
		main.print_message("Cannot delete lanes while a lane is active")
		return
	if deposited_tokens != "0":
		main.print_message("Cannot delete lane with deposited tokens")
		return
	if !main.application_manifest["pending_rewards"][local_network].is_empty():
		main.print_message("Cannot delete lane with pending rewards")
		return

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
	
	var calldata = Ethers.get_calldata(
							"WRITE", 
							main.SCRYPOOL_ABI, 
							"depositTokens", 
							[local_token, Ethers.convert_to_bignum(token_balance, token_decimals)])
					
	var callback_args = {"token_lane": self, "transaction_type": "Deposit"}
	
	# DEBUG
	# change callback node from main(?)
	Ethers.queue_transaction(
				account, 
				local_network, 
				scrypool_contract, 
				calldata, 
				main,
				"get_receipt", 
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
	
	var calldata = Ethers.get_calldata(
							"WRITE", 
							main.SCRYPOOL_ABI, 
							"withdrawTokens", 
							[local_token])
				
	var callback_args = {"token_lane": self, "transaction_type": "Withdrawal"}
	
	# DEBUG
	# change callback node from main(?)
	Ethers.queue_transaction(
				account, 
				local_network, 
				scrypool_contract, 
				calldata, 
				main,
				"get_receipt", 
				callback_args,
				maximum_gas_fee
				)


# NOTE
# The sequence number can be used to query an OffRamp contract to obtain
# the status of a message.  This is useful for checking whether the message
# needs to be manually executed.  Currenly check_pending_rewards() does not
# check the OffRamps, instead only checking ScryPool for any rewards
# that must be manually claimed or failed pools that must be manually exited.
func check_pending_rewards():
	
	if !local_network in main.application_manifest["pending_rewards"].keys():
		main.application_manifest["pending_rewards"][local_network] = []
		main.save_application_manifest()
	
	var pending_rewards = main.application_manifest["pending_rewards"][local_network]
	
	if pending_rewards.is_empty():
		main.print_message("No pending rewards found")
		return
	
	for pending_reward in pending_rewards:
		
		#NOTE
		#For reference:
		
		#pending_reward = {
				#"sequence_number": sequence_number,
				#"message": Any2EVMMessage,
				#"message_id": messageId
			#}
		
		var calldata = Ethers.get_calldata(
						"READ", 
						main.SCRYPOOL_ABI, 
						"checkOrderStatus", 
						[pending_reward["message"]]
						)
						
		var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
		
		Ethers.read_from_contract(
						local_network,
						scrypool_contract,
						calldata,
						self,
						"handle_pending_reward",
						{"pending_reward": pending_reward["message"]}
						)
		
		
func handle_pending_reward(callback):
	if callback["success"]:
		var fill_status = callback["result"][0] #enum
		var rewards_pending = callback["result"][1] #bool
		var pending_reward = callback["callback_args"]["pending_reward"]
		var order_success = false
		match fill_status:
			"0": return # PENDING
			"1": order_success = true # SUCCESS
			"2": claim_reward_or_quit_pool(pending_reward, "quitPool", "Quit Pool") # FAILURE
			
		if order_success:
			if rewards_pending:
				claim_reward_or_quit_pool(pending_reward, "claimOrderReward", "Claim Reward")
			else:
				clear_pending_reward(pending_reward)
		

func claim_reward_or_quit_pool(pending_reward, contract_function, transaction_type):
	var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
	
	var calldata = Ethers.get_calldata(
							"WRITE", 
							main.SCRYPOOL_ABI, 
							contract_function, 
							[pending_reward["message"]])
				
	var callback_args = {
		"token_lane": self, 
		"transaction_type": transaction_type, 
		"pending_reward": pending_reward
		}
	
	Ethers.queue_transaction(
				account, 
				local_network, 
				scrypool_contract, 
				calldata, 
				self,
				"finish_pending_reward", 
				callback_args,
				maximum_gas_fee
				)


func finish_pending_reward(callback):
	if callback["success"]:
		var pending_reward = callback["callback_args"]["pending_reward"]
		clear_pending_reward(pending_reward)
		get_balances()


func clear_pending_reward(pending_reward):
	main.application_manifest["pending_rewards"][local_network].erase(pending_reward)
	main.save_application_manifest()


# DEBUG
func edit_token_lane():
	if main.lane_is_active():	
		main.print_message("Cannot edit lanes while a lane is active")
		return
	var monitored_token_form = main._monitored_token_form.instantiate()
	monitored_token_form.main = main
	monitored_token_form.account = account
	main.add_child(monitored_token_form)
	
	var token_form = token.duplicate()
	var input = monitored_token_form.input
	
	input.get_node("LocalNetwork").text = local_network
	input.get_node("LocalToken").text = local_token
	input.get_node("MinimumTransfer").text = token_form["minimum_transfer"]
	input.get_node("MinimumRewardPercent").text = token_form["minimum_reward_percent"]
	input.get_node("MaximumGasFee").text = maximum_gas_fee
	input.get_node("FlatRateThreshold").text = token_form["flat_rate_threshold"]
	var index = 0
	for network in token_form["remote_networks"].keys():
		var remote_token = token_form["remote_networks"][network]
		var remote_network = input.get_node("RemoteNetworks").get_children()[index]
		remote_network.get_node("RemoteNetwork").text = network
		remote_network.get_node("RemoteToken").text = remote_token
		index += 1
	
	monitored_token_form.check_local_token()
	monitored_token_form.check_remote_tokens()



func handle_approval(callback):
	if callback["success"]:
		var network = callback["network"]
		var approved_contract = callback["callback_args"]["approved_contract"]
		var transaction_type = callback["callback_args"]["transaction_type"]
		main.application_manifest["approvals"][network].push_back(approved_contract)
		main.save_application_manifest()
		
		match transaction_type:
			"Approve ScryPool": deposit_tokens()
