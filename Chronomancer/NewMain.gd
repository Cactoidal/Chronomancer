extends Control


var application_manifest

var available_accounts = {}
var selected_account

var account_tasks = {}

var transaction_queue = {}
var transaction_history = {}

@onready var monitored_token_form = preload("res://scenes/MonitoredTokenForm.tscn")

# Interface variables
var tx_downshift = 0


func _process(delta):
	pass



#####   INTERFACE   #####

func _ready():
	$AddAccount.connect("pressed", open_create_account)
	$SelectedAccount/CreateAccount/CreateAccount.connect("pressed", create_account)
	$SelectedAccount/Login/Login.connect("pressed", login_account)
	$SelectedAccount/AccountManager/ChooseTask/Chronomancer.connect("pressed", select_chronomancer_task)
	$SelectedAccount/AccountManager/ChooseTask/TestCreator.connect("pressed", select_test_creator_task)
	$SelectedAccount/AccountManager/CopyAddress.connect("pressed", copy_address)
	$SelectedAccount/AccountManager/ExportKey.connect("pressed", export_private_key)
	$SelectedAccount/AccountManager/ChangeTask/ChangeTask.connect("pressed", change_task)
	$NetworkSettings.connect("pressed", new_network_form)
	return
	Ethers.register_transaction_log(self, "receive_transaction_object")
	load_ccip_network_info()
	load_application_manifest()
	load_accounts()



func new_network_form():
	pass


func new_test_case_form():
	pass


func new_monitored_token_form():
	var new_form = monitored_token_form.instantiate()
	add_child(new_form)


func load_monitored_tokens():
	# Delete loaded token objects
	
	for monitored_token in application_manifest["monitored_tokens"]:
		#Load tokens
		pass



func print_message(message):
	$Message.text = message
	fadeout($Message)


func fadeout(node):
	node.modulate.a = 1
	var fadeout = create_tween()
	fadeout.tween_property(node,"modulate:a", 0, 4.2).set_trans(Tween.TRANS_LINEAR)
	fadeout.play()


# Opens the passed url in the system's default browser
func open_link(url):
	OS.shell_open(url)



#####   ACCOUNT MANAGEMENT   #####

func load_application_manifest():
	
	if !FileAccess.file_exists("user://MANIFEST"):
		application_manifest = {
			"accounts": [],
			"monitored_tokens": [],
			"test_cases": [],
			"cached_transactions": []
			}
	else:
		var manifest = FileAccess.open("user://MANIFEST", FileAccess.READ).get_as_text()
		var json = JSON.new()
		application_manifest = json.parse_string(manifest)


func save_application_manifest():
	FileAccess.open("user://MANIFEST", FileAccess.WRITE).store_string(str(application_manifest))
	

func load_accounts():
	for account in available_accounts.keys():
		available_accounts[account].queue_free()
	available_accounts = {}
	
	if application_manifest["accounts"] == []:
		$NoAccounts.visible = true
	else:
		for account in application_manifest["accounts"]:
			var account_object = get_account_object(account)
			available_accounts[account] = account_object
			if account == application_manifest["accounts"][0]:
				select_account(account)
			

func get_account_object(account):
	pass


func open_create_account():
	$Task.visible = false
	$SelectedAccount/Login.visible = false
	$SelectedAccount/AccountManager.visible = false
	$SelectedAccount/CreateAccount.visible = true
	$SelectedAccount/CreateAccount/Password.text = ""
	$SelectedAccount/CreateAccount/ImportKey.text = ""
	$SelectedAccount/CreateAccount/AccountName.text = ""


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
	if imported_key.length() != 64 || !imported_key.is_valid_hex_number():
		print_message("Imported key is not valid")
		return
	Ethers.create_account(account_name, password, imported_key)
	application_manifest["accounts"].push_back(account_name)
	save_application_manifest()
	load_accounts()
	select_account(account_name)
	
	password = Ethers.clear_memory()
	password.clear()
	imported_key = Ethers.clear_memory()
	imported_key.clear()
	$SelectedAccount/CreateAccount/Password.text = ""
	$SelectedAccount/CreateAccount/ImportKey.text = ""
	$SelectedAccount/CreateAccount/AccountName.text = ""
	$NoAccounts.visible = false
	


func select_account(account):
	$SelectedAccount/CreateAccount.visible = false
	$SelectedAccount/Login.visible = false
	$SelectedAccount/AccountManager.visible = false
	# DEBUG
	# probably should be account object here
	selected_account = account
	if account in Ethers.logins.keys():
		load_account_manager()
	else:
		$SelectedAccount/Login/AccountName.text = account
		$SelectedAccount/Login/Password.text = ""
		$SelectedAccount/Login.visible = true


func login_account():
	var account_name = $SelectedAccount/Login/AccountName.text
	var password = $SelectedAccount/Login/Password.text
	
	if Ethers.login(account_name, password):
		load_account_manager()
		$SelectedAccount/Login.visible = false
		$SelectedAccount/Login/Password.text = ""
		password = Ethers.clear_memory()
		password.clear()
	
	else:
		print_message("Login failed")
		return
		


func load_account_manager():
	# DEBUG
	var account = selected_account
	$SelectedAccount/AccountManager/ChangeTask.visible = false
	$SelectedAccount/AccountManager/ChooseTask.visible = false
	
	$SelectedAccount/AccountManager/AccountName.text = account
	$SelectedAccount/AccountManager/Address.text = Ethers.get_address(account)
	$SelectedAccount/AccountManager.visible = true
	
	if account in account_tasks.keys():
		load_account_task()
	else:
		$SelectedAccount/AccountManager/ChooseTask.visible = true


func select_chronomancer_task():
	#DEBUG
	account_tasks[selected_account] = "Chronomancer"
	# Update the account object and load the task
	load_account_task()


func select_test_creator_task():
	#DEBUG
	account_tasks[selected_account] = "Test Creator"
	# Update the account object and load the task
	load_account_task()


func load_account_task():
	# DEBUG
	$SelectedAccount/AccountManager/ChangeTask.visible = true
	$SelectedAccount/AccountManager/ChangeTask/Prompt.text = "Current Task:\n" + account_tasks[selected_account]
	#load the appropriate task
	$Task.visible = true


func change_task():
	pass


func copy_address():
	# DEBUG
	var user_address = Ethers.get_address(selected_account)
	DisplayServer.clipboard_set(user_address)
	print_message("Copied Address to Clipboard")


func export_private_key():
	# DEBUG
	var key = Ethers.get_key(selected_account)
	DisplayServer.clipboard_set(key)
	key = Ethers.clear_memory()
	key.clear()
	print_message("Copied Private Key to Clipboard")





#####   MONITORED TOKEN MANAGEMENT   #####

# NOTE
# When adding a monitored network for a monitored token, the serviced network must have an onramp
# onramp contract matching the monitored network.
# There will be a single maximum approval, and then the account can deposit/withdraw
# tokens to ScryPool at will via the monitored token object.  
func add_monitored_token(account, serviced_network, local_token_contract, token_name, token_decimals, monitored_networks, endpoint_contract, minimum, fee):
	var path = "user://" + account + serviced_network + local_token_contract
	
	var new_monitored_token = {
		"account": account,
		"serviced_network": serviced_network,
		"local_token_contract": local_token_contract,
		"token_name": token_name,
		"token_decimals": token_decimals,
		"monitored_networks": monitored_networks,
		"endpoint_contract":endpoint_contract,
		"minimum": minimum,
		"fee": fee,
		"gas_balance": "0",
		"token_balance": "0",
		"token_node": ""	
	}
	var token_json = JSON.new().stringify(new_monitored_token)
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(token_json)
	file.close()


func delete_monitored_token(account, serviced_network, local_token_contract):
	var path = "user://" + account + serviced_network + local_token_contract
	DirAccess.remove_absolute(path)


#####   TEST MANAGEMENT   #####

func add_new_test():
	pass


func delete_test():
	pass



#####   NETWORK MANAGEMENT   #####

# Overwrites Ethers' standard network info.
func load_ccip_network_info():
	var json = JSON.new()
	if FileAccess.file_exists("user://ccip_network_info") != true:
		Ethers.network_info = default_ccip_network_info.duplicate()
		var file = FileAccess.open("user://ccip_network_info", FileAccess.WRITE)
		file.store_string(json.stringify(default_ccip_network_info.duplicate()))
		file.close()
	else:
		var file = FileAccess.open("user://ccip_network_info", FileAccess.READ)
		Ethers.network_info = json.parse_string(file.get_as_text()).duplicate()


func update_network_info():
	var json = JSON.new()
	var file = FileAccess.open("user://ccip_network_info", FileAccess.WRITE)
	file.store_string(json.stringify(Ethers.network_info.duplicate()))
	file.close()
		

func add_network(network, chain_id, rpcs, scan_url, chain_selector, router, onramp_contracts, remote_onramp_contracts):

	var new_network = {
		"chain_id": String(chain_id),
		"rpcs": rpcs,
		"rpc_cycle": 0,
		"gas_balance": "0",
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"scan_url": scan_url,
		#
		"chain_selector": chain_selector,
		"router": router,
		"onramp_contracts": onramp_contracts,
		"monitored_tokens": []
	}
	
	Ethers.network_info[network] = new_network
	
	# Add the new network's onramp to the onramp_contracts of the other networks
	for onramp in remote_onramp_contracts:
		Ethers.network_info[onramp["network"]]["onramp_contracts"][network] = onramp["contract"]
		
	update_network_info()


func remove_network(removed_network):
	if !removed_network in Ethers.network_info.keys():
		print_message("Network not in network info")
		return
	
	Ethers.network_info.erase(removed_network)

	for network in Ethers.network_info:
		network["onramp_contracts"].erase(removed_network)
	
	update_network_info()



#####   TRANSACTION MANAGEMENT   #####

func receive_transaction_object(transaction):
	var local_id = transaction["local_id"]
	
	if !local_id in transaction_history.keys():
		add_new_tx_object(local_id, transaction)
	else:
		var tx_object = transaction_history[local_id]
		update_transaction(tx_object, transaction)


func add_new_tx_object(local_id, transaction):
	var network = transaction["network"]
	var transaction_type = transaction["callback_args"]["transaction_type"]
	var transaction_hash = transaction["transaction_hash"]

	# Build a transaction node for the UI
	var tx_object = instantiate_transaction(network, transaction_type)
	
	# The new transaction node is mapped to the transaction hash, so
	# its status can later be updated by the transaction receipt.
	transaction_history[local_id] = tx_object
	
	# Position the new transaction node beneath the previous one
	$Transactions/Transactions.add_child(tx_object)
	tx_object.position.y += tx_downshift
	
	# The Control node inside the Transactions ScrollContainer must be
	# continuously expanded
	$Transactions/Transactions.custom_minimum_size.y += 128
	
	# Increment the downshift for the next transaction object
	tx_downshift += 108
	
	tx_object.modulate.a = 0
	var fadein = create_tween()
	fadein.tween_property(tx_object,"modulate:a", 1, 2).set_trans(Tween.TRANS_LINEAR)
	fadein.play()


func update_transaction(tx_object, transaction):
	var transaction_hash = transaction["transaction_hash"]
	var transaction_type = transaction["callback_args"]["transaction_type"]
	var network = transaction["network"]
	var tx_status = transaction["tx_status"]
	
	if transaction_hash != "":
		var scan_url = Ethers.network_info[network]["scan_url"]
		var scan_link = tx_object.get_node("Scan Link")
		var ccip_link = tx_object.get_node("CCIP Link")
		
		if !scan_link.visible:
			scan_link.connect("pressed", open_link.bind(scan_url + "tx/" + transaction_hash))
			scan_link.visible = true
		if transaction_type == "CCIP" && !ccip_link.visible:
			ccip_link.connect("pressed", open_link.bind("https://ccip.chain.link/tx/" + transaction_hash))
			ccip_link.visible = true
	
	if tx_status == "success":
		tx_object.get_node("Status").color = Color.GREEN
	elif tx_status != "pending":
		tx_object.get_node("Status").color = Color.RED


func instantiate_transaction(network, transaction_type):
	var new_transaction = Panel.new()
	new_transaction.size = Vector2(146,104)
	var info = Label.new()
	var scan_link = Button.new()
	var ccip_link = Button.new()
	var status = ColorRect.new()
	info.name = "Info"
	status.size = Vector2(15,15)
	status.name = "Status"
	info.text = transaction_type + ":\n" + network
	scan_link.text = "Scan"
	ccip_link.text = "CCIP"
	scan_link.name = "Scan Link"
	ccip_link.name = "CCIP Link"
	scan_link.visible = false
	ccip_link.visible = false
	#scan_link.connect("pressed", open_link.bind(scan_url + "tx/" + transaction_hash))
	#ccip_link.connect("pressed", open_link.bind("https://ccip.chain.link/tx/" + transaction_hash))
	scan_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ccip_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	new_transaction.add_child(info)
	new_transaction.add_child(scan_link)
	new_transaction.add_child(ccip_link)
	new_transaction.add_child(status)
	info.position = Vector2(5,4)
	scan_link.position = Vector2(12,65)
	ccip_link.position = Vector2(86,65)
	status.position = Vector2(127,3)
	
	#if transaction_type != "CCIP":
		#ccip_link.visible = false
		
	return new_transaction



#####   CCIP NETWORK INFO   #####

var default_ccip_network_info = {
	
	"Ethereum Sepolia": 
		{
		"chain_id": "11155111",
		"rpcs": ["https://ethereum-sepolia-rpc.publicnode.com", "https://rpc2.sepolia.org"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.etherscan.io/",
		#
		"chain_selector": "16015286601757825753",
		"router": "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
		#"token_contract": "0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05",
		"onramp_contracts": 
			{
				"Arbitrum Sepolia": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e",
				"Optimism Sepolia": "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d",
				"Base Sepolia": "0x2B70a05320cB069e0fB55084D402343F832556E7",
				"Avalanche Fuji": "0x0477cA0a35eE05D3f9f424d88bC0977ceCf339D4"
			},
		"monitored_tokens": []
		},
		
	"Arbitrum Sepolia": 
		{
		"chain_id": "421614",
		"rpcs": ["https://sepolia-rollup.arbitrum.io/rpc"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.arbiscan.io/",
		#
		"chain_selector": "3478487238524512106",
		"router": "0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165",
		#"token_contract": "0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9",
				"Optimism Sepolia": "0x701Fe16916dd21EFE2f535CA59611D818B017877",
				"Base Sepolia": "0x7854E73C73e7F9bb5b0D5B4861E997f4C6E8dcC6",
				"Avalanche Fuji": "0x1Cb56374296ED19E86F68fA437ee679FD7798DaA"
			},
		"monitored_tokens": []
		},
		
	"Optimism Sepolia": {
		"chain_id": "11155420",
		"rpcs": ["https://sepolia.optimism.io"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia-optimism.etherscan.io/",
		#
		"chain_selector": "5224473277236331295",
		"router": "0x114A20A10b43D4115e5aeef7345a1A71d2a60C57",
		#"token_contract": "0x8aF4204e30565DF93352fE8E1De78925F6664dA7",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a",
				"Arbitrum Sepolia": "0x1a86b29364D1B3fA3386329A361aA98A104b2742",
				"Base Sepolia": "0xe284D2315a28c4d62C419e8474dC457b219DB969",
				"Avalanche Fuji": "0x6b38CC6Fa938D5AB09Bdf0CFe580E226fDD793cE"
			},
		"monitored_tokens": []
	},
	
	"Base Sepolia": {
		"chain_id": "84532",
		"rpcs": ["https://sepolia.base.org", "https://base-sepolia-rpc.publicnode.com"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"scan_url": "https://sepolia.basescan.org/",
		#
		"chain_selector": "10344971235874465080",
		"router": "0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93",
		#"token_contract": "0x88A2d74F47a237a62e7A51cdDa67270CE381555e",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea",
				"Arbitrum Sepolia": "0x58622a80c6DdDc072F2b527a99BE1D0934eb2b50",
				"Optimism Sepolia": "0x3b39Cd9599137f892Ad57A4f54158198D445D147",
				"Avalanche Fuji": "0xAbA09a1b7b9f13E05A6241292a66793Ec7d43357"
			},
		"monitored_tokens": []
	},
	
	"Avalanche Fuji": {
		"chain_id": "43113",
		"rpcs": ["https://avalanche-fuji-c-chain-rpc.publicnode.com"],
		"rpc_cycle": 0,
		"minimum_gas_threshold": 0.0002,
		"maximum_gas_fee": "",
		"scan_url": "https://testnet.snowtrace.io/",
		#
		"chain_selector": "14767482510784806043",
		"router": "0xF694E193200268f9a4868e4Aa017A0118C9a8177",
		#"token_contract": "0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4",
		"onramp_contracts": 
			{
				"Ethereum Sepolia": "0x5724B4Cc39a9690135F7273b44Dfd3BA6c0c69aD",
				"Arbitrum Sepolia": "0x8bB16BEDbFd62D1f905ACe8DBBF2954c8EEB4f66",
				"Optimism Sepolia": "0xC334DE5b020e056d0fE766dE46e8d9f306Ffa1E2",
				"Base Sepolia": "0x1A674645f3EB4147543FCA7d40C5719cbd997362"
			},
		"monitored_tokens": []
	}
}
