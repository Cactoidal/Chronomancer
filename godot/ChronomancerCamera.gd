extends Spatial


#var end_pivot = 57.758934
var end_pivot = Vector3(0, 179.9, 0)
var end_scale = Vector3(0.3, 0.3, 0.3)
var end_upshift = Vector3(0, 1, 0)
var end_downshift = Vector3(0, -0.52, 1.799)
var end_albedo = Color(0, 0, 0, 0.7)
var logo
var overlay
var backdrop
var backdrop_material
var title
var login
var rotation_tweened = false
var position_tweened = false
var logo_upshifted = false
var title_appeared = false
var login_appeared = false

func _ready():
	logo = $ChainlinkMesh
	overlay = get_parent().get_node("Overlay")
	backdrop = get_parent().get_node("Backdrop")
	backdrop_material = backdrop.get_active_material(0)
	title = get_parent().get_node("Title")
	login = get_parent().get_node("Login")



var start_time = 0.2
func _process(delta):
	
	if overlay.modulate.a > 0:
		overlay.modulate.a -= delta/1.4
		if overlay.modulate.a < 0:
			overlay.modulate.a = 0
	
	if overlay.modulate.a == 0:
		start_time -= delta
	
	if start_time < 0 && !rotation_tweened:
		rotation_tweened = true
		$RotationTween.interpolate_property(self, "rotation_degrees", self.rotation_degrees, end_pivot, 4.2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$RotationTween.start()
		$ScaleTween.interpolate_property(logo, "scale", logo.scale, end_scale, 4.2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$ScaleTween.start()
		$AlbedoTween.interpolate_property(backdrop_material, "albedo_color", backdrop_material.albedo_color, end_albedo, 8, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$AlbedoTween.start()
	
	
	if rotation_tweened && !position_tweened && !$ScaleTween.is_active():
		position_tweened = true
		$UpshiftTween.interpolate_property(self, "transform:origin", self.transform.origin, end_upshift, 2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$UpshiftTween.start()
		$LogoDownshiftTween.interpolate_property(logo, "transform:origin", logo.transform.origin, end_downshift, 2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$LogoDownshiftTween.start()
	
	#if tweened && !title_appeared && !$ScaleTween.is_active():
	if position_tweened && !title_appeared:# && !$UpshiftTween.is_active():
		title.modulate.a += delta/2
		if title.modulate.a > 1:
			title.modulate.a = 1
			title_appeared = true
	
	if title_appeared && !login_appeared:
		login.modulate.a += delta/2
		if login.modulate.a > 1:
			login.modulate.a = 1
			login_appeared = true
	
