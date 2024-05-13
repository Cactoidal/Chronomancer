extends TextureRect

var time = 6
var direction
var target

func _ready():
	randomize()
	var color = Color(rand_range(0,1), rand_range(0,1), rand_range(0,1),1)
	modulate = color
	#direction = Vector2(rand_range(-1,1), 1)
	#direction = Vector2(1, rand_range(-1,1))
	$MoveTween.interpolate_property(self, "rect_global_position", rect_global_position, target, 5, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
	$MoveTween.start()
	
func _process(delta):
	
	if !$MoveTween.is_active():
		queue_free()
	
#	time -= delta
#	rect_position += direction
#	if time < 0:
#		queue_free()
