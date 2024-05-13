extends Control

var main_script

var sent_transaction

var ccip_explorer_url = "https://ccip.chain.link/msg/"

var scan_link
var ccip_explorer_link

var color_green = Color(0,1,0,1)
var color_red = Color(1,0,0,1)

func _ready():
	$MainPanel/ScanLink/Button.connect("pressed", self, "open_scanner")
	$MainPanel/CCIPExplorerLink/Button.connect("pressed", self, "open_ccip_explorer")

var transaction = {
	"network": "",
	"token_name": "",
	"type": "",
	"hash": ""
}

func load_info(main, transaction):
	main_script = main
	sent_transaction = transaction
	var network = transaction["network"]
	var tx_type = transaction["type"]
	var tx_hash = transaction["hash"]
	var network_info = Network.network_info.duplicate()
	
	scan_link = network_info[network]["scan_url"] + "tx/" + tx_hash
	$MainPanel/NetworkLogo.texture = load(network_info[network]["logo"])
	
	if tx_type == "order":
		$MainPanel/Info.text = "Filling order on " + network
	
	if tx_type == "approval":
		$MainPanel/Info.text = "Approving endpoint allowance on\n" + network

func was_successful(success, network, block_number=0):
	if success:
		$MainPanel/StatusIndicator.color = color_green
		$MainPanel/StatusLabel.text = "Success"
		if sent_transaction["type"] == "order":
			get_ccip_message_id(network, block_number)
	else:
		$MainPanel/StatusIndicator.color = color_red
		$MainPanel/StatusLabel.text = "Reverted"

func get_ccip_message_id(network, block_number):
	var network_info = Network.network_info.duplicate()
	Ethers.perform_request(
		"eth_getLogs", 
		[{"fromBlock": block_number, "toBlock": block_number, "address": Network.network_info[network]["endpoint_contract"], "topics": ["0x0555709e59fb225fcf12cc582a9e5f7fd8eea54c91f3dc500ab9d8c37c507770"]}], 
		network_info[network]["rpc"], 
		0, 
		self, 
		"load_ccip_explorer_link", 
		{}
		)

func load_ccip_explorer_link(callback):
	if callback["success"] && callback["result"] != []:
		for event in callback["result"]:
			var response = event["data"]
			print(response.right(65))
			var filler_address = FastCcipBot.decode_address(response.right(66))
			print(filler_address)
			if filler_address == Ethers.user_address:
				var messageId = response.left(66)
				print(messageId)
				ccip_explorer_link = ccip_explorer_url + messageId
				$MainPanel/CCIPExplorerLink.visible = true
			
func open_scanner():
	OS.shell_open(scan_link)

func open_ccip_explorer():
	OS.shell_open(ccip_explorer_link)
	



