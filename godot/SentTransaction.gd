extends Control

var main_script
var http
var sent_transaction
var eth_http_request = preload("res://EthRequest.tscn")
var header = "Content-Type: application/json"

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
	http = main_script.get_node("HTTP")
	sent_transaction = transaction
	var network = transaction["network"]
	var tx_type = transaction["type"]
	var tx_hash = transaction["hash"]
	var network_info = main_script.network_info
	
	scan_link = network_info[network]["scan_url"] + "tx/" + tx_hash
	$MainPanel/NetworkLogo.texture = load(network_info[network]["logo"])
	
	if tx_type == "order":
		$MainPanel/Info.text = "Filing order on " + network
		#ccip_explorer_link = ccip_explorer_url + tx_hash
		
		#$MainPanel/CCIPExplorerLink.visible = true
		
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
	perform_ethereum_request(network, "eth_getLogs", [{"fromBlock": block_number, "toBlock": block_number, "address": main_script.network_info[network]["endpoint_contract"], "topics": ["0xe6043a9faa355b4a07ebffd9f3aef89c2067acfa9fcc0a9bf3b2d2361aecb6f8"]}])

func load_ccip_explorer_link(get_result):
	print(get_result)
	if get_result["result"] != []:
		for event in get_result["result"]:
			#if CcipFastBot.decode_address(event["filler"]) == user_address
			var messageId = event["data"]
			ccip_explorer_link = ccip_explorer_url + messageId
			$MainPanel/CCIPExplorerLink.visible = true
			

func open_scanner():
	OS.shell_open(scan_link)

func open_ccip_explorer():
	OS.shell_open(ccip_explorer_link)
	

func perform_ethereum_request(network, method, params, extra_args={}):
	var rpc = main_script.network_info[network]["rpc"]
	
	var http_request = eth_http_request.instance()
	http.add_child(http_request)
	http_request.network = network
	http_request.request_type = method
	http_request.main_script = self
	http_request.extra_args = extra_args
	http_request.connect("request_completed", http_request, "resolve_ethereum_request")
	
	var tx = {"jsonrpc": "2.0", "method": method, "params": params, "id": 7}
	
	http_request.request(rpc, 
	[header], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))

func resolve_ethereum_request(network, method, get_result, extra_args):
	match method:
		"eth_getLogs": load_ccip_explorer_link(get_result)

func ethereum_request_failed(network, method, extra_args):
	pass
