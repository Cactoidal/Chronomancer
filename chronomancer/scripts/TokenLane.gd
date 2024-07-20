extends ColorRect


var token
var main
var account
var active = false

var local_network
var local_token

var gas_balance = "0"
var token_balance = "0"
var deposited_tokens = "0"

var deposit_pending = false
var withdrawal_pending = false


func initialize(_main, _token, _account, _active):
	main = _main
	token = _token.duplicate()
	account = _account
	active = _active
	local_network = token["local_network"]
	local_token = token["local_token"]
	
	if !local_network in main.account_balances[account].keys():
			main.account_balances[account][local_network] = {}
	
	main.account_balances[account][local_network][local_token] = {
					"name": token["token_name"],
					"decimals": token["token_decimals"],
					"balance": "0",
					"deposited_balance": "0"
					}
	
	if active:
		$ToggleMonitoring.text = "Stop Monitoring"
	
	get_token_text()
	get_balances()
	
	$ToggleMonitoring.connect("pressed", toggle_monitoring)
	$ManageLane.connect("pressed", open_lane_manager)
	$DeleteCheck/No.connect("pressed", cancel_lane_deletion)
	$DeleteCheck/Yes.connect("pressed", confirm_lane_deletion)
	
	$LaneManager/Deposit.connect("pressed", approve_tokens)
	$LaneManager/Withdraw.connect("pressed", withdraw_tokens)
	$LaneManager/CheckPending.connect("pressed", check_for_manual_execution)
	$LaneManager/Back.connect("pressed", close_lane_manager)
	$LaneManager/Delete.connect("pressed", open_lane_deletion)



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
			token["token_decimals"],
			self, 
			"update_erc20_balance"
			)





func update_gas_balance(callback):
	if callback["success"]:
		gas_balance = callback["result"]
		main.account_balances[account][local_network]["gas"] = gas_balance
		$GasBalance.text = "Gas: " + gas_balance.left(6)
		$LaneManager/GasBalance.text = "Gas Balance: " + gas_balance.left(6)
	else:
		main.print_message("Failed to retrieve gas balance on " + local_network)


func update_erc20_balance(callback):
	if callback["success"]:
		token_balance = callback["result"]
		main.account_balances[account][local_network][local_token]["balance"] = token_balance
		$LaneManager/TokenBalance.text = token["token_name"] + " Balance: " + token_balance.left(6)
		
		var calldata = Ethers.get_calldata("READ", main.SCRYPOOL_ABI, "userStakedTokens", [Ethers.get_address(account), local_token])
		Ethers.read_from_contract(
						local_network,
						local_token,
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
		$LaneManager/TokenBalance.text = "Tokens: " + deposited_tokens.left(6)
	
	else:
		main.print_message("Failed to retrieve deposited tokens on " + local_network)


func toggle_monitoring(token):
	
	if active:
		active = false
		$ToggleMonitoring.text = "Start Monitoring"
		# DEBUG
		main.active_token_lanes.erase(token)
		return

	#NOTE
	# The lane will still become active even if it isn't ready,
	# it just won't be able to send transactions.
	check_if_ready()
	
	active = true
	$ToggleMonitoring.text = "Stop Monitoring"
	# DEBUG
	main.active_token_lanes.push_back(token)
	
	# DEBUG
	# This could trigger a call to update the balances in main,
	# and check the available liquidity for the token on ScryPool


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


func approve_tokens():
	if token_balance == "0":
		main.print_message("Nothing to deposit")
		return
	if deposit_pending:
		main.print_message("Please wait for pending deposit")
		return
	
	deposit_pending = true
	
	var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
	var params = [scrypool_contract, Ethers.convert_to_bignum(token_balance)]
	var callback_args = {"token_lane": self, "tx_type": "Approval"}
	
	main.queue_transaction(
		account, 
		local_network, 
		local_token, 
		"approve", 
		params, 
		callback_args
		)


func deposit_tokens():
	deposit_pending = true
	
	var scrypool_contract = Ethers.network_info[local_network]["scrypool_contract"]
	var params = [local_token, Ethers.convert_to_bignum(token_balance)]
	var callback_args = {"token_lane": self, "tx_type": "Deposit"}
	
	main.queue_transaction(
		account, 
		local_network, 
		scrypool_contract, 
		"depositTokens", 
		params, 
		callback_args
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
	var callback_args = {"token_lane": self, "tx_type": "Withdrawal"}
	
	main.queue_transaction(
		account, 
		local_network, 
		scrypool_contract, 
		"approve", 
		params, 
		callback_args
		)
	
	

func check_for_manual_execution():
	main.print_message("Not yet implemented")
	

func claim_reward():
	pass


func pause():
	#if out of gas or tokens
	pass


func deposit_complete():
	deposit_pending = false


func withdrawal_complete():
	withdrawal_pending = false


func edit_token_lane():
	var monitored_token_form = main._monitored_token_form.instantiate()
	monitored_token_form.main = main
	monitored_token_form.account = account
	main.add_child(monitored_token_form)
	
	#use the token to fill in all the fields of the form
