extends HTTPRequest

var header = "Content-Type: application/json"

var main_script
var network_info

var pending_orders = []
var pause_order_filling = false

var order_in_queue
var current_method
var signed_data = ""

func _ready():
	main_script = get_parent().main_script
	network_info = get_parent().network_info
	self.connect("request_completed", self, "resolve_ethereum_request")

func _process(delta):
	fill_orders()
	prune_pending_orders(delta)

func intake_order(order):
	var is_new_order = true
	var send_immediately = true
	if !pending_orders.empty():
		send_immediately = false
		for pending_order in pending_orders:
			if pending_order["message"] == order["message"]:
				is_new_order = false
	if is_new_order:
		order["checked"] = false
		order["time_to_prune"] = 240
		order["send_immediately"] = send_immediately
		pending_orders.append(order)

func fill_orders():
	if !pending_orders.empty():
		for pending_order in pending_orders:
			if pending_order["checked"] == false && !pause_order_filling:
				pause_order_filling = true
				pending_order["checked"] = true
				if !pending_order["send_immediately"]:
					check_order_validity(pending_order["order"])
				else:
					pass
					#start track


# it needs to check validity of the order, then the gas balance, then do the tx track
# unlike orderProcessor, perform_ethereum_request needs to handle multiple methods
# and it needs to handle errors appropriately

func check_order_validity(order):
	pass


func resolve_ethereum_request(result, response_code, headers, body):
	match current_method:
		"eth_call": pass
		"eth_getBalance": pass
		"eth_getTransactionCount": pass
		"eth_gasPrice": pass
		"eth_sendRawTransaction": pass
		"eth_getTransactionReceipt": pass

func prune_pending_orders(delta):
	if !pending_orders.empty():
		var deletion_queue = []
		for pending_order in pending_orders:
			pending_order["time_to_prune"] -= delta
			if pending_order["time_to_prune"] < 0:
				deletion_queue.append(pending_order)
		if !deletion_queue.empty():
			for deletable in deletion_queue:
				pending_orders.erase(deletable)
				print("pending order timed out")
