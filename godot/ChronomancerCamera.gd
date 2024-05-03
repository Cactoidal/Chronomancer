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
var main_script
var rotation_tweened = false
var position_tweened = false
var logo_upshifted = false
var title_appeared = false
var login_appeared = false
var logging_in = false
var main_faded_in = false


func _ready():
	logo = $ChainlinkMesh
	overlay = get_parent().get_node("Overlay")
	backdrop = get_parent().get_node("Backdrop")
	backdrop_material = backdrop.get_active_material(0)
	title = get_parent().get_node("Title")
	login = get_parent().get_node("Login")
	main_script = get_parent().get_parent().get_node("Main")
	login.get_node("Button").connect("pressed", self, "login")



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
		title.modulate.a += delta/1.4
		if title.modulate.a > 1:
			title.modulate.a = 1
			title_appeared = true
	
	if title_appeared && !login_appeared:
		login.modulate.a += delta/1.4
		if login.modulate.a > 1:
			login.modulate.a = 1
			login_appeared = true
	
	if logging_in && !main_faded_in && !$TitleTween.is_active():
		main_faded_in = true
		main_script.visible = true
		$MainTween.interpolate_property(main_script, "modulate", main_script.modulate, Color(1,1,1,1), 2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$MainTween.start()
	
func login():
	if login_appeared:
		logging_in = true
		$LoginTween.interpolate_property(login, "modulate", login.modulate, Color(1,1,1,0), 1.4, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$LoginTween.start()
		$TitleTween.interpolate_property(title, "modulate", title.modulate, Color(1,1,1,0), 1.4, Tween.TRANS_QUAD, Tween.EASE_OUT, 0)
		$TitleTween.start()
