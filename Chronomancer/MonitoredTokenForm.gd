extends Control

func _ready():
	$Form/Input/Confirm.connect("pressed", confirm)
	$Form/Input/Cancel.connect("pressed", cancel)
	$Form/ConfirmCancel/Yes.connect("confirm_cancel", cancel)
	$Form/ConfirmCancel/GoBack.connect("go_back", cancel)
	$Form/ConfirmAdd/Confirm.connect("confirm_add", cancel)
	$Form/ConfirmAdd/GoBack.connect("go_back", cancel)


func confirm():
	$Form/Input.visible = false
	$Form/ConfirmAdd.visible = true


func cancel():
	$Form/Input.visible = false
	$Form/ConfirmCancel.visible = true


func go_back():
	$Form/Input.visible = true
	$Form/ConfirmCancel.visible = false
	$Form/ConfirmAdd.visible = false


func confirm_cancel():
	queue_free()


func confirm_add():
	#save
	queue_free()
