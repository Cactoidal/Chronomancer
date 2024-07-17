extends Node3D

# WIP

var transaction_queue = {}
var transaction_history = {}

# Interface variables
var tx_downshift = 0


func _process(delta):
	pass


#####   ACCOUNT MANAGEMENT   #####

func create_account(imported_key=""):
	pass


func export_private_key():
	pass



#####   INTERFACE   #####

func _ready():
	Ethers.register_transaction_log(self, "receive_transaction_object")
	check_for_ccip_network_info()


func new_network_form():
	pass


func new_monitored_token_form():
	pass


func load_monitored_tokens():
	pass


func start_monitoring():
	pass


func stop_monitoring():
	pass


func login_account():
	pass


func show_account_tasks(account):
	pass


func print_message(message):
	#$Message.text = message
	#fadeout($Message)
	print(message)


func fadeout(node):
	node.modulate.a = 1
	var fadeout = create_tween()
	fadeout.tween_property(node,"modulate:a", 0, 3.5).set_trans(Tween.TRANS_LINEAR)
	fadeout.play()


# Opens the passed url in the system's default browser
func open_link(url):
	OS.shell_open(url)



#####   MONITORED TOKEN MANAGEMENT   #####

func add_monitored_token(account, serviced_network, local_token_contract, token_name, token_decimals, monitored_networks, endpoint_contract, minimum, fee):
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


func delete_monitored_token():
	pass


#####   TEST MANAGEMENT   #####

func add_new_test():
	pass


func delete_test():
	pass



#####   NETWORK MANAGEMENT   #####

# Overwrites Ethers' standard network info.
func check_for_ccip_network_info():
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
		

func add_network(network, chain_id, rpcs, scan_url, chain_selector, router, onramp_contracts_by_network, remote_onramp_contracts):
	var onramp_contracts = []
	for onramp in onramp_contracts_by_network:
		onramp_contracts.push_back(onramp["contract"])
		
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
		"onramp_contracts_by_network": onramp_contracts_by_network,
		"monitored_tokens": []
	}
	
	Ethers.network_info[network] = new_network
	
	for onramp in remote_onramp_contracts:
		Ethers.network_info[onramp["network"]]["onramp_contracts"].push_back(onramp["contract"])
		var network_onramp = {
			"network": network,
			"contract": onramp["contract"]
		}
		Ethers.network_info[onramp["network"]]["onramp_contracts_by_network"].push_back(network_onramp)
		
	update_network_info()


func remove_network(removed_network):
	if !removed_network in Ethers.network_info.keys():
		print_message("Network not in network info")
		return
	
	Ethers.network_info.erase(removed_network)

	for network in Ethers.network_info:
		var removed_onramp
		for onramp in network["onramp_contracts_by_network"]:
			if onramp["network"] == removed_network:
				removed_onramp = onramp
				var contract = onramp["contract"]
				network["onramp_contracts"].erase(contract)
		
		if removed_onramp:
			network["onramp_contracts_by_network"].erase(removed_onramp)
	
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
		"onramp_contracts": ["0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e", "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d", "0x2B70a05320cB069e0fB55084D402343F832556E7", "0x0477cA0a35eE05D3f9f424d88bC0977ceCf339D4"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Arbitrum Sepolia",
					"contract": "0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x69CaB5A0a08a12BaFD8f5B195989D709E396Ed4d"
				},
				{
					"network": "Base Sepolia",
					"contract": "0x2B70a05320cB069e0fB55084D402343F832556E7"
				},
				{
					"network": "Avalanche Fuji",
					"contract": "0x0477cA0a35eE05D3f9f424d88bC0977ceCf339D4"
				}
			
		],
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
		"onramp_contracts": ["0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9", "0x701Fe16916dd21EFE2f535CA59611D818B017877", "0x7854E73C73e7F9bb5b0D5B4861E997f4C6E8dcC6", "0x1Cb56374296ED19E86F68fA437ee679FD7798DaA"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x701Fe16916dd21EFE2f535CA59611D818B017877"
				},
				{
					"network": "Base Sepolia",
					"contract": "0x7854E73C73e7F9bb5b0D5B4861E997f4C6E8dcC6"
				},
				{
					"network": "Avalanche Fuji",
					"contract": "0x1Cb56374296ED19E86F68fA437ee679FD7798DaA"
				}
			
		],
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
		"onramp_contracts": ["0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a", "0x1a86b29364D1B3fA3386329A361aA98A104b2742", "0xe284D2315a28c4d62C419e8474dC457b219DB969", "0x6b38CC6Fa938D5AB09Bdf0CFe580E226fDD793cE"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0xC8b93b46BF682c39B3F65Aa1c135bC8A95A5E43a"
				},
				{
					"network": "Arbitrum Sepolia",
					"contract": "0x1a86b29364D1B3fA3386329A361aA98A104b2742"
				},
				{
					"network": "Base Sepolia",
					"contract": "0xe284D2315a28c4d62C419e8474dC457b219DB969"
				},
				{
					"network": "Avalanche Fuji",
					"contract": "0x6b38CC6Fa938D5AB09Bdf0CFe580E226fDD793cE"
				}
			
		],
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
		"onramp_contracts": ["0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea", "0x58622a80c6DdDc072F2b527a99BE1D0934eb2b50", "0x3b39Cd9599137f892Ad57A4f54158198D445D147", "0xAbA09a1b7b9f13E05A6241292a66793Ec7d43357"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea"
				},
				{
					"network": "Arbitrum Sepolia",
					"contract": "0x58622a80c6DdDc072F2b527a99BE1D0934eb2b50"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0x3b39Cd9599137f892Ad57A4f54158198D445D147"
				},
				{
					"network": "Avalanche Fuji",
					"contract": "0xAbA09a1b7b9f13E05A6241292a66793Ec7d43357"
				}
			
		],
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
		"onramp_contracts": ["0x5724B4Cc39a9690135F7273b44Dfd3BA6c0c69aD", "0x8bB16BEDbFd62D1f905ACe8DBBF2954c8EEB4f66", "0xC334DE5b020e056d0fE766dE46e8d9f306Ffa1E2", "0x1A674645f3EB4147543FCA7d40C5719cbd997362"],
		"onramp_contracts_by_network": 
			[
				{
					"network": "Ethereum Sepolia",
					"contract": "0x5724B4Cc39a9690135F7273b44Dfd3BA6c0c69aD"
				},
				{
					"network": "Arbitrum Sepolia",
					"contract": "0x8bB16BEDbFd62D1f905ACe8DBBF2954c8EEB4f66"
				},
				{
					"network": "Optimism Sepolia",
					"contract": "0xC334DE5b020e056d0fE766dE46e8d9f306Ffa1E2"
				},
				{
					"network": "Base Sepolia",
					"contract": "0x1A674645f3EB4147543FCA7d40C5719cbd997362"
				}
			
		],
		"monitored_tokens": []
	}
}
