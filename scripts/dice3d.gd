class_name Dice3D
extends Node3D
## One die: six textured squares round a cube. `toss()` flies it in an arc from a seat,
## tumbles it and lands it (with two small bounces) showing the rolled value on top.
## The result comes from the game rules, the animation just ends on it.

## Faces are built on: +Y 1, +Z 2, +X 3, -X 4, -Z 5, -Y 6 (opposites add to 7).

var size := 0.1
var _final := Basis.IDENTITY
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _axis := Vector3.UP
var _spin := 0.0


func _init(p_size: float) -> void:
	size = p_size
	# face value -> rotation that turns the quad (which faces +Z) to face that side
	var sides := {
		1: Basis(Vector3.RIGHT, -PI / 2),  # +Y
		6: Basis(Vector3.RIGHT, PI / 2),  # -Y
		2: Basis.IDENTITY,  # +Z
		5: Basis(Vector3.UP, PI),  # -Z
		3: Basis(Vector3.UP, PI / 2),  # +X
		4: Basis(Vector3.UP, -PI / 2),  # -X
	}
	for value: int in sides:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := StandardMaterial3D.new()
		m.albedo_texture = PixelTex.die_face(value)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # crisp, readable faces in the dim room
		mi.material_override = m
		var b: Basis = sides[value]
		mi.transform = Transform3D(b, b * Vector3(0, 0, size / 2))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Rotation that puts `value` on top: the side it was built on is turned up to +Y.
static func top_basis(value: int) -> Basis:
	match value:
		6:
			return Basis(Vector3.RIGHT, PI)
		2:
			return Basis(Vector3.RIGHT, -PI / 2)
		5:
			return Basis(Vector3.RIGHT, PI / 2)
		3:
			return Basis(Vector3.BACK, PI / 2)
		4:
			return Basis(Vector3.BACK, -PI / 2)
	return Basis.IDENTITY


## Lying still with `value` up and a random turn about the vertical.
func show_value(value: int) -> void:
	basis = Basis(Vector3.UP, _yaw()) * top_basis(value)


## Square to the camera give or take a little, so the top face is easy to read.
static func _yaw() -> float:
	return randi_range(0, 3) * PI / 2 + randf_range(-0.15, 0.15)


func toss(from: Vector3, to: Vector3, value: int, duration: float) -> void:
	_from = from
	_to = to
	_final = Basis(Vector3.UP, _yaw()) * top_basis(value)
	_axis = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	_spin = randf_range(4.0, 6.0) * PI
	create_tween().tween_method(_fly, 0.0, 1.0, duration)


func _fly(t: float) -> void:
	const AIR := 0.62  # share of the time spent in the air before the first touch
	var pos: Vector3
	if t < AIR:
		var u := t / AIR
		pos = _from.lerp(_to, u)
		pos.y += 0.32 * sin(PI * u)
	else:
		var u := (t - AIR) / (1.0 - AIR)
		pos = _to
		pos.y += 0.06 * absf(sin(2.0 * PI * u)) * (1.0 - u)  # two little bounces
	position = pos
	var ease_t := 1.0 - pow(1.0 - t, 3.0)
	basis = Basis(_axis, _spin * (1.0 - ease_t)) * _final
