class_name CharacterPreview
extends SubViewportContainer
## A small 3D stage showing one character (lobby cards, results screen), optionally turning
## slowly. Its own world, warm light, transparent background.

var model: Character3D
var spin := true


func _init(id: String, preview_size: Vector2, turning := true) -> void:
	custom_minimum_size = preview_size
	stretch = true
	spin = turning
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a6a50")
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.5, 0)
	sun.light_color = Color("ffe2c0")
	vp.add_child(sun)
	model = Character3D.new(id, false)  # standing
	if not turning:
		model.rotation.y = 0.35  # a three-quarter view
	vp.add_child(model)
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	var eye := Vector3(0, 0.95, 2.75)  # not in the tree yet, so no look_at(); head to feet
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.78, 0) - eye), eye)


func _process(delta: float) -> void:
	if spin and model:
		model.rotation.y += delta * 0.6
