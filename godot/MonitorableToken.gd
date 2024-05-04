extends Control

var main_script
var monitorable_token
var approved = false
var monitoring = false

func _ready():
	$MainPanel/Monitor.connect("pressed", self, "toggle_monitor")
	$MainPanel/Close.connect("pressed", self, "close")
	$CloseOverlay/ClosePanel/Cancel.connect("pressed", self, "cancel_close")
	$CloseOverlay/ClosePanel/Remove.connect("pressed", self, "confirm_close")

func load_info(main, token):
	monitorable_token = token
	main_script = main
	var network = monitorable_token["serviced_network"]
	var token_name = monitorable_token["token_name"]
	var monitored_networks = monitorable_token["monitored_networks"]
	var minimum = monitorable_token["minimum"]
	var gas_balance = monitorable_token["gas_balance"]
	var token_balance = monitorable_token["token_balance"]
	var network_info = main_script.network_info
	
	$MainPanel/NetworkLogo.texture = load(network_info[network]["logo"])
	
	var shift = 0
	for monitored_network in monitored_networks:
		var new_logo = TextureRect.new()
		new_logo.texture = load(network_info[monitored_network]["logo"])
		$MonitoredNetworks.add_child(new_logo)
		new_logo.rect_position.x += shift
		shift += 75
	
	$MainPanel/Label.text = "Providing fast transfers of\n" + token_name + "\non " + network + ".  Minimum value: " + String(minimum) + "\n\nMonitoring transfers from:"
	$MainPanel/GasBalance.text = network + " Gas Balance: " + gas_balance
	$MainPanel/TokenBalance.text = token_name + " Balance:\n" + token_balance
	
func toggle_monitor():
	if !approved:
		return
		
	if !monitoring:
		$MainPanel/Monitor.text = "Stop Monitoring"
		monitoring = true
		main_script.active_monitored_tokens.append(monitorable_token)
	
	elif monitoring:
		$MainPanel/Monitor.text = "Start Monitoring"
		monitoring = false
		main_script.active_monitored_tokens.erase(monitorable_token)

func close():
	$CloseOverlay.visible = true

func cancel_close():
	$CloseOverlay.visible = false

#will also need to add in position sorting

func confirm_close():
	var network = monitorable_token["serviced_network"]
	if monitoring:
		toggle_monitor()
	main_script.monitorable_tokens.erase(monitorable_token)
	main_script.network_info[network]["monitored_tokens"].erase(monitorable_token)
	queue_free()
