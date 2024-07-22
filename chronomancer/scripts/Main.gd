extends Control

# Saves accounts, monitored token lanes, test cases, and pending rewards
var application_manifest

# Accounts mapped to their UI object
var available_accounts = {}

# Account in the "selected account" panel, for the purpose of logging in
# and managing an account task
var selected_account

# Accounts mapped to their assigned tasks (Chronomancer or Test Creator)
var account_tasks = {}

# Accounts mapped to networks mapped to gas and token balances
var account_balances = {}  #account -> networks -> gas/tokens

# The currently loaded task interface
var active_task_interface

# Mapping of transaction local_ids to their UI object, 
# for updating transactions in the transaction log
var transaction_history = {}

var _minimum_gas_threshold = "0.0002"

# Reusable UI elements
@onready var _account_object = preload("res://scenes/Account.tscn")
@onready var _transaction_object = preload("res://scenes/Transaction.tscn")
@onready var _network_form = preload("res://scenes/NetworkForm.tscn")

# Interface variables
var tx_downshift = 0
var bridge_slider_amount = 116

# Chronomancer Task variables

var log_poll_timer = 1
var previous_blocks = {}
var loaded_token_lanes = []
var active_token_lanes = []
var logged_messages = []


@onready var _chronomancer_task = preload("res://scenes/ChronomancerTask.tscn")
@onready var _token_lane = preload("res://scenes/TokenLane.tscn")
@onready var _monitored_token_form = preload("res://scenes/MonitoredTokenForm.tscn")

# DEBUG
var test_lane = {
		"local_network": "Base Sepolia",
		"local_token": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e",
		"token_name": "CCIP-BnM",
		"token_decimals": "18",
		"minimum_transfer": "0",
		"minimum_reward_percent": "0",
		"maximum_gas_fee": "0.002",
		"flat_rate_threshold": "100000000",
		"remote_networks": {"Arbitrum Sepolia": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D"}
	}

# Test Creator Task variables


func _ready():
	connect_buttons()
	fadeout($Fadein, 0.7)
	Ethers.register_transaction_log(self, "receive_transaction_object")
	load_ccip_network_info()
	load_application_manifest()
	load_account()



func _process(delta):
	chronomancer_process(delta)
	check_bridge_inputs()



#####   TASK MANAGEMENT   #####


### CHRONOMANCER

# SETUP

func load_chronomancer():
	var fadein = create_tween()
	fadein.tween_property($UI,"modulate:a", 1, 1.2).set_trans(Tween.TRANS_QUAD)
	fadein.play()
	

	var chronomancer_task = _chronomancer_task.instantiate()
	$UI.add_child(chronomancer_task)
	active_task_interface = chronomancer_task
	
	load_token_lanes()
	

func load_token_lanes():
	var chronomancer_task = active_task_interface
	var token_lanes = chronomancer_task.get_node("Task/TokenLanes/TokenLanes/TokenLanes")
	
	for old_lane in loaded_token_lanes:
		old_lane.queue_free()
		token_lanes.custom_minimum_size.y -= 240
	loaded_token_lanes = []
	active_token_lanes = []
	
	var lane_downshift = 1
	
	for _token in application_manifest["monitored_tokens"]:
		
		var token = _token.duplicate()
		token["account"] = selected_account
		
		var token_lane = _token_lane.instantiate()
		token_lanes.add_child(token_lane)
		
		loaded_token_lanes.push_back(token_lane)
		
		token_lane.position = Vector2(13, lane_downshift)
		lane_downshift += 236
		token_lanes.custom_minimum_size.y += 240
		
		token_lane.initialize(self, token, selected_account)


func new_monitored_token_form():
	var monitored_token_form = _monitored_token_form.instantiate()
	monitored_token_form.main = self
	monitored_token_form.account = selected_account
	add_child(monitored_token_form)


# PROCESS

func chronomancer_process(delta):
	if active_token_lanes.is_empty():
		return
	
	log_poll_timer -= delta
	if log_poll_timer < 0:
		log_poll_timer = 1
		get_block_number()


func get_block_number():	
	var remote_onramps = {}
	
	for lane in active_token_lanes:
		var token = lane.token
		# For every token lane, get the set of monitored remote networks.
		for remote_network in token["remote_networks"].keys():
			
			# Each monitored network will become a key in the remote_onramps dictionary.
			# This will allow idempotent additions to each monitored network's array
			# of onramp contracts, across all active lanes.
			if !remote_network in remote_onramps.keys():
				remote_onramps[remote_network] = []
			
			# Map each monitored network to the specific set of onramp contracts to be queried
			# for CCIP messages.
			var onramp = Ethers.network_info[remote_network]["onramp_contracts"][token["local_network"]]
			if !onramp in remote_onramps[remote_network]:
				remote_onramps[remote_network].push_back(onramp)
	
	# Get the most recent block number.
	for network in remote_onramps.keys():
		Ethers.perform_request(
		"eth_blockNumber", 
		[], 
		network, 
		self, 
		"get_ccip_messages",
		{"onramps": remote_onramps[network]}
		)


func get_ccip_messages(callback):
	if callback["success"]:
		
		var latest_block = callback["result"]
		var network = callback["network"]
		var onramps = callback["callback_args"]["onramps"]
		
		if !network in previous_blocks.keys():
			previous_blocks[network] = "0"
		
		if latest_block == previous_blocks[network]:
			return
		
		var previous_block = previous_blocks[network]
		var params = {
			"fromBlock": previous_block, 
			# The array of onramp contracts
			"address": onramps, 
			# The "CCIPSendRequested" event topic hash
			"topics": ["0xd0c3c799bf9e2639de44391e7f524d229b2b55f5b1ea94b2bf7da42f7243dddd"]
			}
		
		if previous_block != "latest":
			params["toBlock"] = latest_block
		
		previous_blocks[network] = latest_block
		
		Ethers.perform_request(
			"eth_getLogs", 
			[params],
			network,
			self,
			"decode_EVM2EVM_message"
			)
	else:
		print_message("Failed to retrieve block number from " + callback["network"])
	


func decode_EVM2EVM_message(callback):
	if callback["success"]:
		var network = callback["network"]
		for event in callback["result"]:
			
			# First, check the destination chain by determining which
			# OnRamp sent the message.
			var onramp_contract = event["address"]
			var destination_network = ""
			
			# The list of onramp contracts is duplicated to avoid changes from
			# propagating to the ccip_network_info dictionary.
			var onramp_list = Ethers.network_info[network]["onramp_contracts"].duplicate()
			for onramp_network in onramp_list.keys():
				var onramp = onramp_list[onramp_network]
				# Some RPC nodes return contract addresses with lowercase letters,
				# while some do not.
				if onramp != onramp_contract:
					onramp = onramp.to_lower()
				if onramp == onramp_contract:
					destination_network = onramp_network

			# The message data will be an EVM2EVM message in the form of
			# ABI encoded bytes.
			var message = event["data"]
			
			# You can ABI encode and decode values manually by using
			# the Calldata singleton.  You must provide the input
			# or output types along with the values to encode/decode.
			var EVM2EVMMessageStruct = {
				"type": "tuple",
				
				"components": [
					{"type": "uint64"}, # sourceChainSelector
					{"type": "address"}, # sender
					{"type": "address"}, # receiver
					{"type": "uint64"}, # sequenceNumber
					{"type": "uint256"}, # gasLimit
					{"type": "bool"}, # strict
					{"type": "uint64"}, # nonce
					{"type": "address"}, # feeToken
					{"type": "uint256"}, # feeTokenAmount
					{"type": "bytes"}, # data
					{"type": "tuple[]", # tokenAmounts
					"components": [
						{"type": "address"}, # token
						{"type": "uint256"} # amount
						]},
					{"type": "bytes[]"}, # sourceTokenData
					{"type": "bytes32"} # messageId
				]
				
				}
			
			# The ABI Decoder will return an array containing the tuple, which
			# can be accessed at index 0.  Once accessed, the 13 elements of the 
			# EVM2EVM message can be accessed at their index.
			var decoded_message = Calldata.abi_decode([EVM2EVMMessageStruct], message)[0]
			
			# Check if the receiver is the Chronomancer endpoint.
			var receiver = decoded_message[2]
			var chronomancer_endpoint = Ethers.network_info[destination_network]["chronomancer_endpoint"]
			
	
			if receiver.to_lower() != chronomancer_endpoint.to_lower():
				return
			
			# Check if the token is a monitored token, and
			# get the matching local token.
			var tokenAmounts = decoded_message[10]
			# Some CCIP messages do not transmit tokens.
			if tokenAmounts.is_empty():
				return
			# Right now, only checks for a single token.
			var token_contract = tokenAmounts[0][0]
			var token_amount = tokenAmounts[0][1]
			
			var local_token = ""
			var token_decimals
			var minimum_reward_percent
			var flat_rate_threshold
			var minimum_transfer
			var maximum_gas_fee
			var account
			var scrypool_liquidity
			var deposited_liquidity
			
			for lane in active_token_lanes:
				var token = lane.token.duplicate()
				scrypool_liquidity = lane.total_liquidity
				deposited_liquidity = lane.deposited_tokens
				if token["local_network"].to_lower() == destination_network.to_lower():
					for remote_network in token["remote_networks"]:
						if token["remote_networks"][remote_network].to_lower() == token_contract.to_lower():
							local_token = token["local_token"]
							token_decimals = token["token_decimals"]
							minimum_reward_percent = Ethers.convert_to_bignum(token["minimum_reward_percent"], token_decimals)
							flat_rate_threshold = Ethers.convert_to_bignum(token["flat_rate_threshold"], token_decimals)
							minimum_transfer = Ethers.convert_to_bignum(token["minimum_transfer"], token_decimals)
							maximum_gas_fee = token["maximum_gas_fee"]
							account = token["account"]
			
			
			if local_token == "":
				return
			
			# Check if the recipient is the Chronomancer endpoint.
			var data = Calldata.abi_decode(
				[{"type": "address"},
				{"type": "uint256"},
				{"type": "bytes"}
				], 
				decoded_message[9]
				)
			
			if data[0].to_lower() == chronomancer_endpoint.to_lower():
				return
			
			
			# Check that user's deposited tokens meet or exceed the minimum transfer amount.
			if Ethers.big_uint_math(deposited_liquidity, "LESS THAN OR EQUAL", minimum_transfer):
				return
			
			
			# Check that the transfer amount meets or exceeds the minimum.
			if Ethers.big_uint_math(token_amount, "LESS THAN OR EQUAL", minimum_transfer):
				return
			
			
			# Check that the reward meets or exceeds the set reward percentage
			# and flat rate threshold.  Also check that the reward does not equal
			# or exceed the transfer amount.
			
			var expected_minimum_reward = "0"
			
			if minimum_reward_percent != "0":
				expected_minimum_reward = Ethers.big_uint_math(token_amount, "DIVIDE", minimum_reward_percent)
			
			var message_reward = data[1]
			
			if Ethers.big_uint_math(message_reward, "LESS THAN", expected_minimum_reward):
				if flat_rate_threshold != "":
					if Ethers.big_uint_math(message_reward, "LESS THAN", flat_rate_threshold):
						return
				else:
					return
			
			
			# Reward cannot be equal to or larger than the transfer amount
			if Ethers.big_uint_math(token_amount, "LESS THAN OR EQUAL", message_reward):
				return
		
			# Won't attempt if ScryPool liquidity is too low
			if Ethers.big_uint_math(scrypool_liquidity, "LESS THAN", token_amount):
				print_message("Valid message rejected: ScryPool liquidity too low")
				return
	
			# Check that this message hasn't already been recorded.
			var messageId = decoded_message[12]
			
			if messageId in logged_messages:
				return
			else:
				logged_messages.push_back(messageId)
			
			
			# Convert the EVM2EVM message to an Any2EVM Message,
			# swapping the local token for the remote token.
			# Then queue the order fill transaction.
			var Any2EVMMessageStruct = {
				"type": "tuple",
				
				"components": [
					{"type": "bytes32"}, # messageId
					{"type": "uint64"}, # sourceChainSelector
					{"type": "bytes"}, # ABI-encoded sender
					{"type": "bytes"}, # ABI-encoded data
					{"type": "tuple[]", # tokenAmounts
					"components": [
						{"type": "address"}, # token
						{"type": "uint256"} # amount
						]},
				]
				
				}
			
			var Any2EVMMessage = [
				messageId, #messageId
				decoded_message[0], # sourceChainSelector
				Calldata.abi_encode([{"type": "address"}], [decoded_message[1]]), # ABI-encoded sender
				decoded_message[9], # ABI-encoded data
				[[local_token, token_amount]] # destTokenAmounts
			]
			
			var sequence_number = decoded_message[4]
			
			var pending_reward = {
				"sequence_number": sequence_number,
				"message": Any2EVMMessage,
				"message_id": messageId
			}
			
			var calldata = Ethers.get_calldata(
							"WRITE", 
							SCRYPOOL_ABI, 
							"joinPool", 
							[Calldata.abi_encode([Any2EVMMessageStruct], [Any2EVMMessage])])
				
			var callback_args = {"transaction_type": "Order Fill", "ccip_message_id": messageId, "pending_reward": pending_reward}
	
			var ratio = 1
			if minimum_transfer != "0":
				ratio = Ethers.big_uint_math(token_amount, "DIVIDE", minimum_transfer)
			
			maximum_gas_fee = float(maximum_gas_fee) * float(ratio);
	
			Ethers.queue_transaction(
							account, 
							destination_network, 
							Ethers.network_info[destination_network]["scrypool_contract"], 
							calldata, 
							self,
							"get_receipt", 
							callback_args,
							str(maximum_gas_fee)
							)





func log_pending_reward(network, pending_reward):
	if !network in application_manifest["pending_rewards"].keys():
		application_manifest["pending_rewards"][network] = []
	application_manifest["pending_rewards"][network].push_back(pending_reward)
	save_application_manifest()


func mint():
	var network = $UI/Bridge/Sender.text
	
	if !network in Ethers.network_info:
		print_message("CCIP-BnM contract not found for " + network)
		return
	if Transaction.pending_transaction(selected_account, network):
		print_message("Transaction ongoing on " + network)
		return
	if !has_network_gas(network):
		print_message("Insufficient gas on " + network)
		return
		
	var token_contract = Ethers.network_info[network]["bnm_contract"]
	print_message("Copied CCIP-BnM contract to clipboard")
	DisplayServer.clipboard_set(token_contract)
	
	var address = Ethers.get_address(selected_account)
	
	var function_selector = {
		"name": "drip",
		"inputs": [{"type": "address"}]
	}
	
	var calldata = {
		"calldata": Calldata.get_function_selector(function_selector) + Calldata.abi_encode( [{"type": "address"}], [address] )
		}
		
	Ethers.send_transaction(
				selected_account, 
				network, 
				token_contract, 
				calldata, 
				self, 
				"get_receipt", 
				{"transaction_type": "Mint", "token_contract": token_contract}
				)






#####   ACCOUNT MANAGEMENT   #####

# DEBUG
func load_application_manifest():
	# DEBUG
	if !FileAccess.file_exists("user://MANIFEST"):
		application_manifest = {
			"account": "",
			"monitored_tokens": [test_lane],
			"test_cases": [],
			"cached_transactions": [],
			"approvals": {},
			"pending_rewards": {}
			}
		# DEBUG
		#save_application_manifest()
	else:
		var manifest = FileAccess.open("user://MANIFEST", FileAccess.READ).get_as_text()
		var json = JSON.new()
		application_manifest = json.parse_string(manifest)


func save_application_manifest():
	FileAccess.open("user://MANIFEST", FileAccess.WRITE).store_string(str(application_manifest))
	

func load_account():
	var account = application_manifest["account"]
	if account == "":
		$SelectedAccount/CreateAccount.visible = true
	else:
		$SelectedAccount/CreateAccount.visible = false
		$SelectedAccount/Login.visible = true
		
		selected_account = account
		$SelectedAccount/Login/AccountName.text = account
		$SelectedAccount/Login/Password.text = ""


func create_account():
	var account_name = $SelectedAccount/CreateAccount/AccountName.text
	var password = $SelectedAccount/CreateAccount/Password.text
	var imported_key = $SelectedAccount/CreateAccount/ImportKey.text
	if Ethers.account_exists(account_name):
		print_message("Account " + account_name + " already exists")
		return
	if account_name == "":
		print_message("Need to input account name")
		return
	if password == "":
		print_message("Need to input password")
		return
	if imported_key != "":
		if imported_key.length() != 64 || !imported_key.is_valid_hex_number():
			print_message("Imported key is not valid")
			return
	Ethers.create_account(account_name, password, imported_key)
	application_manifest["account"] = account_name
	save_application_manifest()
	load_account()
	
	password = Ethers.clear_memory()
	password.clear()
	imported_key = Ethers.clear_memory()
	imported_key.clear()
	$SelectedAccount/CreateAccount/Password.text = ""
	$SelectedAccount/CreateAccount/ImportKey.text = ""
	$SelectedAccount/CreateAccount/AccountName.text = ""


func login_account():
	var account_name = $SelectedAccount/Login/AccountName.text
	var password = $SelectedAccount/Login/Password.text
	
	if Ethers.login(account_name, password):
		
		password = Ethers.clear_memory()
		password.clear()
		$SelectedAccount/Login/Password.text = ""
		$SelectedAccount/Login.visible = false
		
		$SelectedAccount/AccountManager.visible = true
		$SelectedAccount/AccountManager/AccountName.text = account_name
		$SelectedAccount/AccountManager/Address.text = Ethers.get_address(account_name)
		
		account_balances[account_name] = {}
		
		load_chronomancer()
		
	else:
		print_message("Login failed")
		return

#
#func get_balances(account, networks):
	#for network in networks:
		#Ethers.get_gas_balance(network, account, self, "update_gas_balance")
#
#
#func update_gas_balance(callback):
	#if callback["success"]:
		#var network = callback["network"]
		#var account = callback["account"]
		#
		#initialize_network_balance(network)
		#
		#for token in account_balances[account][network].keys():
			#if token != "gas":
				#var decimals = account_balances[account][network][token]["decimals"]
				#Ethers.get_erc20_balance(
						#network, 
						#Ethers.get_address(account), 
						#token, 
						#decimals, 
						#self, 
						#"update_erc20_balance",
						#{"token": token}
						#)
#
#func update_erc20_balance(callback):
	#if callback["success"]:
		#var network = callback["network"]
		#var account = callback["account"]
		#var token = callback["callback_args"]["token"]
		#account_balances[account][network][token]["balance"] = callback["result"]


func load_account_manager():
	var account = selected_account

	$SelectedAccount/AccountManager.visible = true
	$SelectedAccount/AccountManager/AccountName.text = account
	$SelectedAccount/AccountManager/Address.text = Ethers.get_address(account)
	load_chronomancer()


func copy_address():
	var user_address = Ethers.get_address(selected_account)
	DisplayServer.clipboard_set(user_address)
	print_message("Copied Address to Clipboard")


func export_private_key():
	var key = Ethers.get_key(selected_account).hex_encode()
	DisplayServer.clipboard_set(key)
	key = Ethers.clear_memory()
	key.clear()
	print_message("Copied Private Key to Clipboard")



#####   NETWORK MANAGEMENT   #####

# Because this node is lower on the scene tree than Ethers.gd,
# calling this function in _ready() will overwrite Ethers' standard network info.
func load_ccip_network_info():
	var json = JSON.new()
	# DEBUG
	if FileAccess.file_exists("user://ccip_network_info") != true:
		Ethers.network_info = default_ccip_network_info.duplicate()
		var file = FileAccess.open("user://ccip_network_info", FileAccess.WRITE)
		file.store_string(json.stringify(default_ccip_network_info.duplicate()))
		file.close()
	else:
		var file = FileAccess.open("user://ccip_network_info", FileAccess.READ)
		Ethers.network_info = json.parse_string(file.get_as_text()).duplicate()


func new_network_form():
	var network_form = _network_form.instantiate()
	network_form.main = self
	add_child(network_form)



#####   TRANSACTION LOGGING   #####


func receive_transaction_object(transaction):
	var local_id = transaction["local_id"]
	
	if !local_id in transaction_history.keys():
		add_new_tx_object(local_id, transaction)
	else:
		var tx_object = transaction_history[local_id]
		update_transaction(tx_object, transaction)


func add_new_tx_object(local_id, transaction):
	var network = transaction["network"]
	var account = transaction["account"]
	var transaction_type = transaction["callback_args"]["transaction_type"]
	var transaction_hash = transaction["transaction_hash"]
	var transaction_log = $UI/TransactionLog/Transactions/Transactions

	# Build a transaction node for the UI
	var tx_object = _transaction_object.instantiate()
	tx_object.get_node("NetworkName").text = network
	tx_object.get_node("AccountName").text = account
	tx_object.get_node("TransactionType").text = transaction_type
	
	if transaction_type == "Order Fill":
		var ccip_message_id = transaction["callback_args"]["ccip_message_id"]
		tx_object.get_node("CCIP").visible = true
		tx_object.get_node("CCIP").connect("pressed", open_link.bind("https://ccip.chain.link/msg/" + ccip_message_id))
	
	# The new transaction node is mapped to the transaction hash, so
	# its status can later be updated by the transaction receipt.
	transaction_history[local_id] = tx_object
	
	# Position the new transaction node beneath the previous one
	transaction_log.add_child(tx_object)
	tx_object.position = Vector2(15, tx_downshift)
	
	# The Control node inside the Transactions ScrollContainer must be
	# continuously expanded
	transaction_log.custom_minimum_size.y += 128
	
	# Increment the downshift for the next transaction object
	tx_downshift += 116
	
	# Once the log is full, start autoscrolling down
	if tx_downshift >= 580:
		var autoscroll = create_tween()
		var distance = transaction_log.get_parent().scroll_vertical + 116
		autoscroll.tween_property(transaction_log.get_parent(), "scroll_vertical", distance, 0.5).set_trans(Tween.TRANS_QUAD)
		autoscroll.play()
	
	tx_object.modulate.a = 0
	var fadein = create_tween()
	fadein.tween_property(tx_object,"modulate:a", 1, 2).set_trans(Tween.TRANS_LINEAR)
	fadein.play()


# DEBUG
# Update balances
func update_transaction(tx_object, transaction):
	var transaction_hash = transaction["transaction_hash"]
	var transaction_type = transaction["callback_args"]["transaction_type"]
	var network = transaction["network"]
	var tx_status = transaction["tx_status"]
	
	var lane
	if "token_lane" in transaction["callback_args"].keys():
		lane = transaction["callback_args"]["token_lane"]
	
	if transaction_hash != "":
		if "scan_url" in Ethers.network_info[network].keys():
			var scan_url = Ethers.network_info[network]["scan_url"]
			var scan_link = tx_object.get_node("Scan")
			
			if !scan_link.visible:
				scan_link.connect("pressed", open_link.bind(scan_url + "tx/" + transaction_hash))
				scan_link.visible = true
		
		if transaction_type in ["CCIP Bridge", "Order Fill"]:
			var ccip_link = tx_object.get_node("CCIP")
			if !ccip_link.visible:
				ccip_link.connect("pressed", open_link.bind("https://ccip.chain.link/tx/" + transaction_hash))
				ccip_link.visible = true
			
			# DEBUG
			#https://ccip.chain.link/msg/
			
	
	if tx_status == "SUCCESS":
		var receipt = transaction["transaction_receipt"]
		if receipt["status"] == "0x1":
			tx_object.get_node("Status").color = Color.GREEN
			
			if transaction_type in ["Mint", "Approve Router", "CCIP Bridge"]:
				get_bridge_gas_balance(network)
			if transaction_type in ["Mint", "CCIP Bridge"]:
					var token_contract = transaction["callback_args"]["token_contract"]
					get_bridge_token_balance(network, token_contract)
			
			if transaction_type == "Order Fill":
				var pending_reward = transaction["callback_args"]["pending_reward"]
				log_pending_reward(network, pending_reward)
				
				for token_lane in active_token_lanes:
					if token_lane.local_network == network:
						token_lane.get_balances()
			
		else:
			tx_object.get_node("Status").color = Color.RED
			
		if lane:
			update_token_lane(lane, transaction_type, true)
			
	elif tx_status != "PENDING":
		tx_object.get_node("Status").color = Color.RED
		tx_object.get_node("Error").visible = true
		tx_object.get_node("Error").connect("pressed", print_message.bind(tx_status))
		if lane:
			update_token_lane(lane, transaction_type, false)


func update_token_lane(token_lane, transaction_type, success):
	if transaction_type in ["Deposit", "Withdrawal"]:
		token_lane.get_balances()
		match transaction_type:
			"Deposit": token_lane.deposit_pending = false
			"Withdrawal": token_lane.withdrawal_pending = false
	else:
		Ethers.get_gas_balance(
			token_lane.local_network, 
			selected_account, 
			token_lane, 
			"update_gas_balance"
			)




#####   INTERFACE   #####


func print_message(message):
	if $Message.get_children().size() > 1:
		return
		
	for node in $Message.get_children():
		node.queue_free()
	var label = Label.new()
	label.text = message
	$Message.add_child(label)
	fadeout(label, 4.2)


func fadeout(node, time):
	node.modulate.a = 1
	var fadeout = create_tween()
	fadeout.tween_property(node,"modulate:a", 0, time).set_trans(Tween.TRANS_LINEAR)
	fadeout.play()


# Opens the passed url in the system's default browser
func open_link(url):
	OS.shell_open(url)


func connect_buttons():
	$SelectedAccount/CreateAccount/CreateAccount.connect("pressed", create_account)
	$SelectedAccount/Login/Login.connect("pressed", login_account)
	$SelectedAccount/AccountManager/CopyAddress.connect("pressed", copy_address)
	$SelectedAccount/AccountManager/ExportKey.connect("pressed", export_private_key)
	$NetworkSettings.connect("pressed", new_network_form)
	$UI/Bridge.connect("pressed", slide_bridge)
	$UI/Bridge/Mint.connect("pressed", mint)
	$UI/Bridge/Initiate.connect("pressed", initiate_bridge)
	$UI/NewLane.connect("pressed", new_monitored_token_form)


var slid_out = false
var sliding = false
func slide_bridge():
	if sliding == true:
		return
	sliding = true
	var slide = create_tween()
	var next_position_y = $UI/Bridge.position.y
	if slid_out:
		next_position_y += bridge_slider_amount
	else:
		next_position_y -= bridge_slider_amount
		
	slide.tween_property($UI/Bridge,"position:y", next_position_y, 0.3).set_trans(Tween.TRANS_QUAD)
	slide.tween_callback(slide_bridge_callback)
	slide.play()


func slide_bridge_callback():
	sliding = false
	if slid_out:
		slid_out = false
	else:
		slid_out = true



####     BRIDGING    ####

var previous_sender_network = ""
var previous_token_contract = ""
func check_bridge_inputs():
	var sender_network = $UI/Bridge/Sender.text
	var token_contract = $UI/Bridge/Token.text
	if sender_network != previous_sender_network:
		$UI/Bridge/GasBalance.visible = false
		$UI/Bridge/TokenBalance.visible = false
		previous_sender_network = sender_network
		if sender_network in Ethers.network_info.keys():
			get_bridge_gas_balance(sender_network)
			if is_valid_address(token_contract):
				get_bridge_token_balance(sender_network, token_contract)
	
	
	if token_contract != previous_token_contract:
		$UI/Bridge/TokenBalance.visible = false
		previous_token_contract = token_contract
		if is_valid_address(token_contract) && sender_network in Ethers.network_info.keys():
			get_bridge_token_balance(sender_network, token_contract)
	

func get_bridge_gas_balance(network):
	Ethers.get_gas_balance(network, selected_account, self, "update_bridge_gas_balance")


func update_bridge_gas_balance(callback):
	if callback["success"]:
		var network = callback["network"]
		#var gas_symbol = Ethers.network_info[network]["gas_symbol"]
		$UI/Bridge/GasBalance.text = "Gas: " + callback["result"].left(6)
		$UI/Bridge/GasBalance.visible = true
		if !network in account_balances[selected_account].keys():
			account_balances[selected_account][network] = {}
		account_balances[selected_account][network]["gas"] = callback["result"]


func get_bridge_token_balance(network, token_contract):
	Ethers.get_erc20_info(
				network, 
				Ethers.get_address(selected_account), 
				token_contract, 
				self, 
				"update_bridge_token_balance", 
				{"token_contract": token_contract}
				)


func update_bridge_token_balance(callback):
	if callback["success"]:
		var network = callback["network"]
		var token_name = callback["result"][0]
		var token_decimals = callback["result"][1]
		var token_balance = callback["result"][2]
		var token_contract = callback["callback_args"]["token_contract"]
		
		initialize_network_balance(network, token_contract)
		account_balances[selected_account][network][token_contract]["name"] = token_name
		account_balances[selected_account][network][token_contract]["decimals"] = token_decimals
		account_balances[selected_account][network][token_contract]["balance"] = token_balance
			
		$UI/Bridge/TokenBalance.text = token_name + ": " + token_balance
		$UI/Bridge/TokenBalance.visible = true


func has_network_gas(network):
	initialize_network_balance(network)
	var minimum_gas_threshold = Ethers.convert_to_bignum(_minimum_gas_threshold, 18)
	var gas = Ethers.convert_to_bignum(account_balances[selected_account][network]["gas"], 18)
	
	if Ethers.big_uint_math(gas, "LESS THAN", minimum_gas_threshold):
		return false
	
	return true


func has_enough_tokens(network, token_contract, _amount):
	initialize_network_balance(network, token_contract)
	var token_info = account_balances[selected_account][network][token_contract]
	
	var decimals = token_info["decimals"]
	
	var balance = Ethers.convert_to_bignum(token_info["balance"], decimals)
	var amount = Ethers.convert_to_bignum(_amount, decimals)
	
	if amount == "0":
		print_message("Transfer amount is zero")
		return false
	
	if Ethers.big_uint_math(balance, "LESS THAN", amount):
		return false
	
	return true


func initialize_network_balance(network, token_contract=""):
	if !network in account_balances[selected_account].keys():
		account_balances[selected_account][network] = {}
	if !"gas" in account_balances[selected_account][network].keys():
		account_balances[selected_account][network]["gas"] = "0"

	if token_contract == "":
		return
	
	if !token_contract in account_balances[selected_account][network].keys():
		account_balances[selected_account][network][token_contract] = {
					"name": "",
					"decimals": "18",
					"balance": "0",
					"deposited_balance": "0",
					"total_liquidity": "0"
					}


func has_approval(network, token_contract):
	if !network in application_manifest["approvals"].keys():
		application_manifest["approvals"][network] = []
		save_application_manifest()
	if !token_contract in application_manifest["approvals"][network]:
		return false
	return true


func is_valid_address(address):
	#Address must be a string
	if typeof(address) == 4:
		if address.begins_with("0x") && address.length() == 42:
			if address.trim_prefix("0x").is_valid_hex_number():
				return true
	return false



func initiate_bridge():
	var sender_network = $UI/Bridge/Sender.text
	var destination_network = $UI/Bridge/Destination.text
	var token_contract = $UI/Bridge/Token.text
	var amount = $UI/Bridge/Amount.text
	
	if !sender_network in Ethers.network_info.keys():
		print_message("Invalid sender network")
		return
	if !destination_network in Ethers.network_info.keys():
		print_message("Invalid destination network")
		return
		
	# DEBUG
	if Ethers.network_info[destination_network]["chronomancer_endpoint"] == "":
		print_message("No Chronomancer endpoint found for " + destination_network)
		return
		
	if !is_valid_address(token_contract):
		print_message("Invalid token contract")
		return
	if Transaction.pending_transaction(selected_account, sender_network):
		print_message("Transaction ongoing on " + sender_network)
		return
	if !has_network_gas(sender_network):
		print_message("Insufficient gas on " + sender_network)
		return
	if !has_enough_tokens(sender_network, token_contract, amount):
		print_message("Token balance less than transfer amount")
		return
	
	var router = Ethers.network_info[sender_network]["router"]
	var bridge_form = {
		"sender_network": sender_network,
		"destination_network": destination_network,
		"token_contract": token_contract,
		"amount": amount
	}
	
	if !has_approval(sender_network, router):
		Ethers.approve_erc20_allowance(
				selected_account, 
				sender_network, 
				token_contract, 
				router, 
				"MAX", 
				self, 
				"handle_approval", 
				{"transaction_type": "Approve Router", "approved_contract": router, "bridge_form": bridge_form}
				)
	else:
		bridge(bridge_form)


func handle_approval(callback):
	if callback["success"]:
		var network = callback["network"]
		var approved_contract = callback["callback_args"]["approved_contract"]
		var transaction_type = callback["callback_args"]["transaction_type"]
		application_manifest["approvals"][network].push_back(approved_contract)
		save_application_manifest()
		
		match transaction_type:
			"Approve Router": bridge(callback["callback_args"]["bridge_form"])


func bridge(bridge_form):
	var sender_network = bridge_form["sender_network"]
	var destination_network = bridge_form["destination_network"]
	var token_contract = bridge_form["token_contract"]
	var decimals = account_balances[selected_account][sender_network][token_contract]["decimals"]
	var amount = Ethers.convert_to_bignum(bridge_form["amount"], decimals)
	
	# DEBUG
	var chronomancer_endpoint = Ethers.network_info[destination_network]["chronomancer_endpoint"]
	
	# DEBUG
	var recipient = Ethers.get_address(selected_account)
	var reward = Ethers.convert_to_bignum("0.001", decimals)
	var test_payload = Calldata.abi_encode( [{"type": "string"}], ["test"] )
	
	var data = Calldata.abi_encode([{"type": "address"}, {"type": "uint256"}, {"type": "bytes"}], [recipient, reward, test_payload])
	
	var EVMTokenAmount = [
		token_contract,
		amount
	]
	
	var EVMExtraArgsV1 = [
		"90000" # Destination gas limit
	]
	
	# EVM2Any messages expect some of their parameters to 
	# be ABI encoded and sent as bytes.
	var extra_args = "97a657c9" + Calldata.abi_encode( [{"type": "tuple", "components":[{"type": "uint256"}]}], [EVMExtraArgsV1] )
	
	var EVM2AnyMessage = [
		# DEBUG
		Calldata.abi_encode( [{"type": "address"}], [chronomancer_endpoint] ), # ABI-encoded Chronomancer endpoint address
		data, # Data payload, as bytes
		[EVMTokenAmount], # EVMTokenAmounts
		"0x0000000000000000000000000000000000000000", # Fee address (address(0) = native token)
		extra_args # Extra args
	]
	
	var chain_selector = Ethers.network_info[destination_network]["chain_selector"]
	
	var calldata = Ethers.get_calldata("READ", CCIP_ROUTER, "getFee", [chain_selector, EVM2AnyMessage])
	
	var router = Ethers.network_info[sender_network]["router"]
	Ethers.read_from_contract(
				sender_network, 
				router, 
				calldata, 
				self, 
				"send_bridge_transaction", 
				{"chain_selector": chain_selector, "EVM2AnyMessage": EVM2AnyMessage, "token_contract": token_contract}
				)


func send_bridge_transaction(callback):
	
	if callback["success"]:
		var network = callback["network"]
		var callback_args = callback["callback_args"]
		var EVM2AnyMessage = callback_args["EVM2AnyMessage"]
		var chain_selector = callback_args["chain_selector"]
		var router = Ethers.network_info[network]["router"]
		var token_contract = callback_args["token_contract"]
		
		# Because a contract read can return multple values,
		# successful returns from "read_from_contract()" will 
		# always arrive as an array of decoded outputs.
		var fee = callback["result"][0]
		
		# Bump up the fee to decrease chances of a revert.
		# Excess value sent will be refunded by the CCIP router
		fee = float(Ethers.convert_to_smallnum(fee))
		fee *= 1.25
		fee = Ethers.convert_to_bignum(str(fee))
		
		var calldata = Ethers.get_calldata("WRITE", CCIP_ROUTER, "ccipSend", [chain_selector, EVM2AnyMessage])
		
		# The fee value acquired above is passed as the "value" parameter.
		Ethers.send_transaction(
			selected_account, 
			network, 
			router, 
			calldata, 
			self, 
			"get_receipt", 
			{"transaction_type": "CCIP Bridge", "token_contract": token_contract}, 
			"0.1", 
			fee
			)


# DEBUG
func get_receipt(callback):
	#DEBUG
	# update balances
	pass



#####   CCIP NETWORK INFO   #####

var default_ccip_network_info = {
	
	"Ethereum Sepolia": 
		{
		"chain_id": "11155111",
		"rpcs": ["https://ethereum-sepolia-rpc.publicnode.com", "https://rpc2.sepolia.org"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.etherscan.io/",
		"gas_symbol": "ETH",
		#
		"chain_selector": "16015286601757825753",
		"router": "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
		"bnm_contract": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
		"onramp_contracts": 
			{
				"Arbitrum Sepolia": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e",
				"Optimism Sepolia": "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d",
				"Base Sepolia": "0x2B70a05320cB069e0fB55084D402343F832556E7",
				"Avalanche Fuji": "0x0477cA0a35eE05D3f9f424d88bC0977ceCf339D4",
				"BNB Chain Testnet": "0xD990f8aFA5BCB02f95eEd88ecB7C68f5998bD618",
				"Polygon Amoy": "0x9f656e0361Fb5Df2ac446102c8aB31855B591692",
				"Wemix Testnet": "0xedFc22336Eb0B9B11Ff37C07777db27BCcDe3C65",
				"Gnosis Chiado": "0x3E842E3A79A00AFdd03B52390B1caC6306Ea257E",
				"Mode Sepolia": "0xc630fbD4D0F6AEB00aD0793FB827b54fBB78e981",
				"Blast Sepolia": "0xDB75E9D9ca7577CcBd7232741be954cf26194a66",
				"Celo Alfajores": "0x3C86d16F52C10B2ff6696a0e1b8E0BcfCC085948"
			}
		},
		
	"Arbitrum Sepolia": 
		{
		"chain_id": "421614",
		"rpcs": ["https://sepolia-rollup.arbitrum.io/rpc"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.arbiscan.io/",
		"gas_symbol": "ETH",
		#
		"chain_selector": "3478487238524512106",
		"router": "0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165",
		"bnm_contract": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9",
				"Optimism Sepolia": "0x701Fe16916dd21EFE2f535CA59611D818B017877",
				"Base Sepolia": "0x7854E73C73e7F9bb5b0D5B4861E997f4C6E8dcC6",
				"Avalanche Fuji": "0x1Cb56374296ED19E86F68fA437ee679FD7798DaA",
				"Wemix Testnet": "0xBD4106fBE4699FE212A34Cc21b10BFf22b02d959",
				"Gnosis Chiado": "0x973CbE752258D32AE82b60CD1CB656Eebb588dF0"
			}
		},
		
	"Optimism Sepolia": {
		"chain_id": "11155420",
		"rpcs": ["https://sepolia.optimism.io"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia-optimism.etherscan.io/",
		"gas_symbol": "ETH",
		#
		"chain_selector": "5224473277236331295",
		"router": "0x114A20A10b43D4115e5aeef7345a1A71d2a60C57",
		"bnm_contract": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a",
				"Arbitrum Sepolia": "0x1a86b29364D1B3fA3386329A361aA98A104b2742",
				"Base Sepolia": "0xe284D2315a28c4d62C419e8474dC457b219DB969",
				"Avalanche Fuji": "0x6b38CC6Fa938D5AB09Bdf0CFe580E226fDD793cE",
				"Polygon Amoy": "0x2Cf26fb01E9ccDb831414B766287c0A9e4551089",
				"Wemix Testnet": "0xc7E53f6aB982af7A7C3e470c8cCa283d3399BDAd",
				"Gnosis Chiado": "0x835a5b8e6CA17c2bB5A336c93a4E22478E6F1C8A"
			}
	},
	
	"Base Sepolia": {
		"chain_id": "84532",
		"rpcs": ["https://sepolia.base.org", "https://base-sepolia-rpc.publicnode.com"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.basescan.org/",
		"gas_symbol": "ETH",
		#
		"chain_selector": "10344971235874465080",
		"router": "0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93",
		"bnm_contract": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e",
		"chronomancer_endpoint": "0x5e2080208a22A74E02D900cA774131278B5d9A57",
		"scrypool_contract": "0xCC21bBA3E9da45bAC54f25be3914ad6ED18dCFdd",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea",
				"Arbitrum Sepolia": "0x58622a80c6DdDc072F2b527a99BE1D0934eb2b50",
				"Optimism Sepolia": "0x3b39Cd9599137f892Ad57A4f54158198D445D147",
				"Avalanche Fuji": "0xAbA09a1b7b9f13E05A6241292a66793Ec7d43357",
				"BNB Chain Testnet": "0xD806966beAB5A3C75E5B90CDA4a6922C6A9F0c9d",
				"Gnosis Chiado": "0x2Eff2d1BF5C557d6289D208a7a43608f5E3FeCc2",
				"Mode Sepolia": "0x3d0115386C01436870a2c47e6297962284E70BA6"
			}
	},
	
	"Avalanche Fuji": {
		"chain_id": "43113",
		"rpcs": ["https://avalanche-fuji-c-chain-rpc.publicnode.com"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://testnet.snowtrace.io/",
		"gas_symbol": "AVAX",
		#
		"chain_selector": "14767482510784806043",
		"router": "0xF694E193200268f9a4868e4Aa017A0118C9a8177",
		"bnm_contract": "0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x5724B4Cc39a9690135F7273b44Dfd3BA6c0c69aD",
				"Arbitrum Sepolia": "0x8bB16BEDbFd62D1f905ACe8DBBF2954c8EEB4f66",
				"Optimism Sepolia": "0xC334DE5b020e056d0fE766dE46e8d9f306Ffa1E2",
				"Base Sepolia": "0x1A674645f3EB4147543FCA7d40C5719cbd997362",
				"BNB Chain Testnet": "0xF25ECF1Aad9B2E43EDc2960cF66f325783245535",
				"Polygon Amoy": "0x610F76A35E17DA4542518D85FfEa12645eF111Fc",
				"Wemix Testnet": "0x677B5ab5C8522d929166c064d5700F147b15fa33",
				"Gnosis Chiado": "0x1532e5b204ee2b2244170c78E743CB9c168F4DF9"
			}
	},
	
	"BNB Chain Testnet": {
		"chain_id": "97",
		"rpcs": ["https://bsc-testnet-rpc.publicnode.com"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://testnet.bscscan.com",
		"gas_symbol": "BNB",
		#
		"chain_selector": "13264668187771770619",
		"router": "0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f",
		"bnm_contract": "0xbFA2ACd33ED6EEc0ed3Cc06bF1ac38d22b36B9e9",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0xB1DE44B04C00eaFe9915a3C07a0CaeA4410537dF",
				"Base Sepolia": "0x3E807220Ca84b997c0d1928162227b46C618e0c5",
				"Avalanche Fuji": "0xa2515683E99F50ADbE177519A46bb20FfdBaA5de",
				"Polygon Amoy": "0xf37CcbfC04adc1B56a46B36F811D52C744a1AF78",
				"Wemix Testnet": "0x89268Afc1BEA0782a27ba84124E3F42b196af927",
				"Gnosis Chiado": "0x8735f991d41eA9cA9D2CC75cD201e4B7C866E63e"
			}
	},
	
	"Wemix Testnet": {
		"chain_id": "1112",
		"rpcs": ["https://api.test.wemix.com"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://testnet.wemixscan.com",
		"gas_symbol": "WEMIX",
		#
		"chain_selector": "9284632837123596123",
		"router": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"bnm_contract": "0xF4E4057FbBc86915F4b2d63EEFFe641C03294ffc",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x4d57C6d8037C65fa66D6231844785a428310a735",
				"Arbitrum Sepolia": "0xA9DE3F7A617D67bC50c56baaCb9E0373C15EbfC6",
				"Optimism Sepolia": "0x1961a7De751451F410391c251D4D4F98D71B767D",
				"Avalanche Fuji": "0xC4aC84da458ba8e40210D2dF94C76E9a41f70069",
				"BNB Chain Testnet": "0x5AD6eed6Be0ffaDCA4105050CF0E584D87E0c2F1",
				"Polygon Amoy": "0xd55148e841e76265B484d399eC71b7076ecB1216",
				"Kroma Sepolia": "0x428C4dc89b6Bf908B82d77C9CBceA786ea8cc7D0"
			}
	},
	
	"Gnosis Chiado": {
		"chain_id": "10200",
		"rpcs": ["https://1rpc.io/gnosis"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://gnosis-chiado.blockscout.com",
		"gas_symbol": "ETH",
		#
		"chain_selector": "8871595565390010547",
		"router": "0x19b1bac554111517831ACadc0FD119D23Bb14391",
		"bnm_contract": "0xA189971a2c5AcA0DFC5Ee7a2C44a2Ae27b3CF389",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x4ac7FBEc2A7298AbDf0E0F4fDC45015836C4bAFe",
				"Arbitrum Sepolia": "0x473b49fb592B54a4BfCD55d40E048431982879C9",
				"Optimism Sepolia": "0xAae733212981e06D9C978Eb5148F8af03F54b6EF",
				"Base Sepolia": "0x41b4A51cAfb699D9504E89d19D71F92E886028a8",
				"Avalanche Fuji": "0x610F76A35E17DA4542518D85FfEa12645eF111Fc",
				"BNB Chain Testnet": "0xE48E6AA1fc7D0411acEA95F8C6CaD972A37721D4",
				"Polygon Amoy": "0x01800fCDd892e37f7829937271840A6F041bE62E"
			}
	},
	
	"Polygon Amoy": {
		"chain_id": "80002",
		"rpcs": ["https://polygon-amoy-bor-rpc.publicnode.com", "https://rpc-amoy.polygon.technology", "https://polygon-amoy.drpc.org"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://amoy.polygonscan.com",
		"gas_symbol": "MATIC",
		#
		"chain_selector": "16281711391670634445",
		"router": "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2",
		"bnm_contract": "0xcab0EF91Bee323d1A617c0a027eE753aFd6997E4",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x35347A2fC1f2a4c5Eae03339040d0b83b09e6FDA",
				"Optimism Sepolia": "0xA52cDAeb43803A80B3c0C2296f5cFe57e695BE11",
				"Avalanche Fuji": "0x8Fb98b3837578aceEA32b454f3221FE18D7Ce903",
				"BNB Chain Testnet": "0xC6683ac4a0F62803Bec89a5355B36495ddF2C38b",
				"Wemix Testnet": "0x26546096F64B5eF9A1DcDAe70Df6F4f8c2E10C61",
				"Gnosis Chiado": "0x2331F6D614C9Fd613Ff59a1aB727f1EDf6c37A68"
			}
	},
	
	"Kroma Sepolia": {
		"chain_id": "2358",
		"rpcs": ["https://api.sepolia.kroma.network"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.kromascan.com",
		"gas_symbol": "ETH",
		#
		"chain_selector": "5990477251245693094",
		"router": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"bnm_contract": "0x6AC3e353D1DDda24d5A5416024d6E436b8817A4e",
		"onramp_contracts": 
			{
				"Wemix Testnet": "0x6ea155Fc77566D9dcE01B8aa5D7968665dc4f0C5"
			}
	},
	
	"Celo Alfajores": {
		"chain_id": "44787",
		"rpcs": ["https://alfajores-forno.celo-testnet.org"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://alfajores.celoscan.io",
		"gas_symbol": "CELO",
		#
		"chain_selector": "3552045678561919002",
		"router": "0xb00E95b773528E2Ea724DB06B75113F239D15Dca",
		"bnm_contract": "0x7e503dd1dAF90117A1b79953321043d9E6815C72",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x16a020c4bbdE363FaB8481262D30516AdbcfcFc8"
			}
	},
	
	"Blast Sepolia": {
		"chain_id": "168587773",
		"rpcs": ["https://sepolia.blast.io", "https://blast-sepolia.drpc.org"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.blastscan.io",
		"gas_symbol": "ETH",
		#
		"chain_selector": "2027362563942762617",
		"router": "0xfb2f2A207dC428da81fbAFfDDe121761f8Be1194",
		"bnm_contract": "0x8D122C3e8ce9C8B62b87d3551bDfD8C259Bb0771",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x85Ef19FC4C63c70744995DC38CAAEC185E0c619f"
			}
	},
	
	"Mode Sepolia": {
		"chain_id": "919",
		"rpcs": ["https://sepolia.mode.network"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": "0.0002",
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.explorer.mode.network",
		"gas_symbol": "ETH",
		#
		"chain_selector": "829525985033418733",
		"router": "0xc49ec0eB4beb48B8Da4cceC51AA9A5bD0D0A4c43",
		"bnm_contract": "0xB9d4e1141E67ECFedC8A8139b5229b7FF2BF16F5",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0xfFdE9E8c34A27BEBeaCcAcB7b3044A0A364455C9",
				"Base Sepolia": "0x73f7E074bd7291706a0C5412f51DB46441B1aDCB"
			}
	}
	
}




# ABI

var SCRYPOOL_ABI = [
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_endpoint",
				"type": "address"
			}
		],
		"stateMutability": "nonpayable",
		"type": "constructor"
	},
	{
		"inputs": [],
		"name": "CannotQuitPool",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "router",
				"type": "address"
			}
		],
		"name": "InvalidRouter",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "MessageNotReceived",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "TooLateToJoinPool",
		"type": "error"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "FailedToFillOrder",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "FilledOrder",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "MessageReceived",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "address",
				"name": "",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"name": "RewardDisbursed",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"name": "availableLiquidity",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"components": [
					{
						"internalType": "bytes32",
						"name": "messageId",
						"type": "bytes32"
					},
					{
						"internalType": "uint64",
						"name": "sourceChainSelector",
						"type": "uint64"
					},
					{
						"internalType": "bytes",
						"name": "sender",
						"type": "bytes"
					},
					{
						"internalType": "bytes",
						"name": "data",
						"type": "bytes"
					},
					{
						"components": [
							{
								"internalType": "address",
								"name": "token",
								"type": "address"
							},
							{
								"internalType": "uint256",
								"name": "amount",
								"type": "uint256"
							}
						],
						"internalType": "struct Client.EVMTokenAmount[]",
						"name": "destTokenAmounts",
						"type": "tuple[]"
					}
				],
				"internalType": "struct Client.Any2EVMMessage",
				"name": "message",
				"type": "tuple"
			}
		],
		"name": "ccipReceive",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			}
		],
		"name": "checkOrderStatus",
		"outputs": [
			{
				"internalType": "enum ScryPool.fillStatus",
				"name": "",
				"type": "uint8"
			},
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			}
		],
		"name": "claimOrderReward",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_token",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "_amount",
				"type": "uint256"
			}
		],
		"name": "depositTokens",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "getRouter",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			}
		],
		"name": "joinPool",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "_message",
				"type": "bytes"
			}
		],
		"name": "quitPool",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes4",
				"name": "interfaceId",
				"type": "bytes4"
			}
		],
		"name": "supportsInterface",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "pure",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"name": "userStakedTokens",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_token",
				"type": "address"
			}
		],
		"name": "withdrawTokens",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	}
]


var CCIP_ROUTER = [
  {
	"inputs": [],
	"name": "InsufficientFeeTokenAmount",
	"type": "error"
  },
  {
	"inputs": [],
	"name": "InvalidMsgValue",
	"type": "error"
  },
  {
	"inputs": [
	  {
		"internalType": "uint64",
		"name": "destChainSelector",
		"type": "uint64"
	  }
	],
	"name": "UnsupportedDestinationChain",
	"type": "error"
  },
  {
	"inputs": [
	  {
		"internalType": "uint64",
		"name": "destinationChainSelector",
		"type": "uint64"
	  },
	  {
		"components": [
		  {
			"internalType": "bytes",
			"name": "receiver",
			"type": "bytes"
		  },
		  {
			"internalType": "bytes",
			"name": "data",
			"type": "bytes"
		  },
		  {
			"components": [
			  {
				"internalType": "address",
				"name": "token",
				"type": "address"
			  },
			  {
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			  }
			],
			"internalType": "struct Client.EVMTokenAmount[]",
			"name": "tokenAmounts",
			"type": "tuple[]"
		  },
		  {
			"internalType": "address",
			"name": "feeToken",
			"type": "address"
		  },
		  {
			"internalType": "bytes",
			"name": "extraArgs",
			"type": "bytes"
		  }
		],
		"internalType": "struct Client.EVM2AnyMessage",
		"name": "message",
		"type": "tuple"
	  }
	],
	"name": "ccipSend",
	"outputs": [
	  {
		"internalType": "bytes32",
		"name": "",
		"type": "bytes32"
	  }
	],
	"stateMutability": "payable",
	"type": "function"
  },
  {
	"inputs": [
	  {
		"internalType": "uint64",
		"name": "destinationChainSelector",
		"type": "uint64"
	  },
	  {
		"components": [
		  {
			"internalType": "bytes",
			"name": "receiver",
			"type": "bytes"
		  },
		  {
			"internalType": "bytes",
			"name": "data",
			"type": "bytes"
		  },
		  {
			"components": [
			  {
				"internalType": "address",
				"name": "token",
				"type": "address"
			  },
			  {
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			  }
			],
			"internalType": "struct Client.EVMTokenAmount[]",
			"name": "tokenAmounts",
			"type": "tuple[]"
		  },
		  {
			"internalType": "address",
			"name": "feeToken",
			"type": "address"
		  },
		  {
			"internalType": "bytes",
			"name": "extraArgs",
			"type": "bytes"
		  }
		],
		"internalType": "struct Client.EVM2AnyMessage",
		"name": "message",
		"type": "tuple"
	  }
	],
	"name": "getFee",
	"outputs": [
	  {
		"internalType": "uint256",
		"name": "fee",
		"type": "uint256"
	  }
	],
	"stateMutability": "view",
	"type": "function"
  },
  {
	"inputs": [
	  {
		"internalType": "uint64",
		"name": "chainSelector",
		"type": "uint64"
	  }
	],
	"name": "getSupportedTokens",
	"outputs": [
	  {
		"internalType": "address[]",
		"name": "tokens",
		"type": "address[]"
	  }
	],
	"stateMutability": "view",
	"type": "function"
  },
  {
	"inputs": [
	  {
		"internalType": "uint64",
		"name": "chainSelector",
		"type": "uint64"
	  }
	],
	"name": "isChainSupported",
	"outputs": [
	  {
		"internalType": "bool",
		"name": "supported",
		"type": "bool"
	  }
	],
	"stateMutability": "view",
	"type": "function"
  }
]
