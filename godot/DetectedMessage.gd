extends Spatial


var time = 15
var move_array = [0,0,0]
var move_vec: Vector3
var move_vector = Vector3(1,0,1)

func _ready():
	move_vector = Vector3(rand_range(-1,1), rand_range(-1,1), rand_range(-1,1))

func _process(delta):
	$MeshInstance.global_transform.origin += move_vector * delta
	time -= delta
	if time < 0:
		queue_free()
