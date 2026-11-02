class_name MenuScene
extends TavernView
## The main menu backdrop (after the user's reference picture: a warm, candle-lit table in
## the middle of the scene): a bird's eye view straight down on the table, swaying slowly
## from side to side; all four heroes seated round it playing. Each in turn throws the dice; a good roll gets a
## cheer and coins from the pot, a poor one a pained face while a rival gloats; now and then
## someone flings a card at a rival. Friendly, but everyone wants to win. Silent.

## Seats 1-4 (0 is unused here): evenly round the table, one on each side as seen from above.
const MENU_SEATS := [Vector3.ZERO, Vector3(-1.5, 0, 0), Vector3(0, 0, -1.5),
	Vector3(1.5, 0, 0), Vector3(0, 0, 1.5)]
const FACE_TOWARD := Vector3.ZERO  # everyone faces the middle of the table
const TURN_SECONDS := 3.2
const POT := Vector3(-0.32, 0.0, 0.32)  # the coin pile on the felt (y = table top)
const THROWN := ["blind", "truce", "bad_luck", "attack", "no_shop"]

var _flicker: Array[OmniLight3D] = []
var _flicker_base: Array[float] = []
var _stacks: Array[Node3D] = [null]  # per seat: its coin stack on the felt
var _turn := 0
var _turn_left := 1.5
var _coin_mat: StandardMaterial3D
var _cam_home := Vector3.ZERO
## Camera sway: a spring pulls it towards a side that swaps every few seconds, so it eases
## out, glides over and settles with a touch of overshoot (inertia), never a fixed beat.
const CAM_FOCUS := Vector3(0, 0.76, 0.0)  # the middle of the table
const SWAY := 0.5  # metres to each side
const SWAY_SPRING := 0.5
const SWAY_DAMP := 1.0
var _sway := 0.0
var _sway_v := 0.0
var _sway_target := SWAY
var _sway_left := 7.0


func _ready() -> void:
	super()
	_coin_mat = _mat(Color("e0b040"))
	_coin_mat.metallic = 0.6
	_coin_mat.roughness = 0.45
	# bird's eye: high above, looking almost straight down on the felt (a little tilt keeps
	# the heroes' heads round the rim readable)
	_camera.fov = 52
	_cam_home = Vector3(0.0, 5.5, 1.3)
	_camera.position = _cam_home
	_camera.look_at(CAM_FOCUS, Vector3.FORWARD)  # looking down: screen-up = the far side
	_camera.h_offset = -1.1  # the table sits right of the menu buttons
	_build_menu_light()
	_build_menu_props()


## Seat the four heroes (`ids`: four character ids, in seat order).
func seat_all(ids: Array) -> void:
	seat_pos.assign(MENU_SEATS)
	_base_modulate.assign([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])  # block() flashes from these
	var chair := _mat(Color("4a2f1c"))
	for seat in range(1, MENU_SEATS.size()):
		var p: Vector3 = MENU_SEATS[seat]
		var facing := FACE_TOWARD - Vector3(p.x, 0, p.z)
		var yaw := atan2(facing.x, facing.z)
		_chair(p, facing, chair)
		var c := Character3D.new(ids[(seat - 1) % ids.size()])
		c.position = p
		c.rotation.y = yaw
		c.scale = Vector3.ONE * CHARACTER_SCALE
		viewport.add_child(c)
		_characters.append(c)
		# their coin stack and cards on the felt in front of them
		var toward := -Vector3(p.x, 0, p.z).normalized()
		var spot := p * 0.58 + Vector3(0, TABLE_TOP + 0.01, 0)
		var side := toward.cross(Vector3.UP) * 0.22
		var stack := Node3D.new()
		stack.position = spot - side
		viewport.add_child(stack)
		_stacks.append(stack)
		for k in randi_range(3, 7):
			_add_coin(stack)
		for k in 2:
			_box(Vector3(0.16, 0.01, 0.22), spot + side + Vector3(0, 0.006 * k, 0),
				_mat(Color("27306b")), atan2(toward.x, toward.z) + 0.25 - k * 0.35)
		# soft warm fill on each face
		_light(p - Vector3(p.x, 0, p.z).normalized() * 0.7 + Vector3(0, 1.4, 0.2), Color("ffcf98"), 0.45, 1.6)


func _process(delta: float) -> void:
	super(delta)
	# candle flames waver
	var now := Time.get_ticks_msec() / 1000.0
	for i in _flicker.size():
		_flicker[i].light_energy = _flicker_base[i] * (0.86 + 0.1 * sin(now * 7.3 + i * 1.7) + 0.06 * sin(now * 17.0 + i))
	_sway_camera(delta, now)
	if _characters.size() < MENU_SEATS.size():
		return
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = TURN_SECONDS
		_turn = _turn % (MENU_SEATS.size() - 1) + 1
		_play_turn(_turn)


func _sway_camera(delta: float, now: float) -> void:
	_sway_left -= delta
	if _sway_left <= 0.0:
		_sway_left = randf_range(6.0, 8.0)
		_sway_target = -signf(_sway_target) * SWAY * randf_range(0.8, 1.0)
	_sway_v += (SWAY_SPRING * (_sway_target - _sway) - SWAY_DAMP * _sway_v) * delta
	_sway += _sway_v * delta
	# gliding sideways high over the table, a faint rise and fall, a lean into the turn
	var arc := Vector3(_sway, 0.06 * sin(now * 0.3), 0)
	_camera.position = _cam_home + arc
	_camera.look_at(CAM_FOCUS + Vector3(_sway * 0.2, 0, 0), Vector3.FORWARD)
	_camera.rotate_object_local(Vector3.FORWARD, -_sway_v * 0.08)


## One hero's turn: throw the dice, then react; every few turns a card for a rival.
func _play_turn(seat: int) -> void:
	var me := character(seat)
	var rival := (seat + randi_range(0, 2)) % 4 + 1
	if rival == seat:
		rival = seat % 4 + 1
	if randf() < 0.3:
		me.throw_gesture(0.5)
		var id: String = THROWN.pick_random()
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			throw_card(seat, rival, CardDB.get_card(id), 0.6))
		get_tree().create_timer(0.85).timeout.connect(func() -> void:
			if randf() < 0.4:
				block(rival)
			else:
				character(rival).hurt()
				character(rival).tremble(0.3))
		return
	var values: Array[int] = [randi_range(1, 6), randi_range(1, 6), randi_range(1, 6)]
	me.throw_gesture(0.55)
	get_tree().create_timer(0.25).timeout.connect(throw_dice.bind(seat, values, 0.9))
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		if values[0] + values[1] + values[2] >= 11:
			me.cheer(0.9)
			character(rival).hurt()
			_pay(seat, 3)
		else:
			me.hurt()
			character(rival).cheer(0.8)
			_pay(seat, 1))


## Coins hop from the pot to `seat`'s stack.
func _pay(seat: int, count: int) -> void:
	var stack := _stacks[seat]
	if stack.get_child_count() > 12:  # spent at the shop: start small again
		for c in stack.get_children():
			c.queue_free()
		for k in 3:
			_add_coin(stack)
	for k in count:
		var coin := MeshInstance3D.new()
		coin.mesh = _coin_mesh()
		coin.material_override = _coin_mat
		var from := POT + Vector3(0, TABLE_TOP + 0.05, 0)
		var to := stack.position + Vector3(0, 0.014 * (stack.get_child_count() + k) + 0.008, 0)
		coin.position = from
		viewport.add_child(coin)
		var t := coin.create_tween()
		t.tween_interval(k * 0.12)
		t.tween_method(func(f: float) -> void:
			coin.position = from.lerp(to, f) + Vector3(0, 0.3 * sin(PI * f), 0)
			coin.rotation.x = f * TAU * 2, 0.0, 1.0, 0.45)
		t.tween_callback(func() -> void:
			coin.queue_free()
			_add_coin(stack))


func _coin_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.045
	mesh.bottom_radius = 0.045
	mesh.height = 0.012
	mesh.radial_segments = 16
	mesh.rings = 1
	return mesh


func _add_coin(stack: Node3D) -> void:
	var coin := MeshInstance3D.new()
	coin.mesh = _coin_mesh()
	coin.material_override = _coin_mat
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var n := stack.get_child_count()
	coin.position = Vector3(randf_range(-0.004, 0.004), 0.014 * n + 0.006, randf_range(-0.004, 0.004))
	stack.add_child(coin)


# ---------- the room, warmer ----------

func _build_menu_light() -> void:
	var env: Environment = (viewport.get_child(0) as WorldEnvironment).environment
	env.background_color = Color("0c0806")
	env.ambient_light_color = Color("5a3a26")
	env.ambient_light_energy = 0.45
	env.fog_enabled = true  # the far walls sink into warm dark
	env.fog_light_color = Color("1a0f08")
	env.fog_density = 0.09
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15
	# a big warm lamp over the table and a sunset glow through a window on the left
	_flicker_light(Vector3(0, 2.3, 0.0), Color("ffb868"), 1.5, 4.0)
	var window := _quad(Vector2(1.0, 1.4), _mat(Color("ff9a48"), null, Vector3.ONE, true))
	window.position = Vector3(-3.48, 1.8, -1.4)
	window.rotation.y = PI / 2
	window.transparency = 0.25
	for bar: float in [-0.25, 0.25]:  # window bars
		_box(Vector3(0.04, 1.4, 0.05), Vector3(-3.46, 1.8, -1.4 + bar), _mat(Color("2a1a10")))
	_box(Vector3(0.04, 0.05, 1.0), Vector3(-3.46, 1.8, -1.4), _mat(Color("2a1a10")))
	_light(Vector3(-3.0, 1.9, -1.4), Color("ff8a3c"), 0.9, 3.0)


func _build_menu_props() -> void:
	# a three-armed candlestick on the felt, between two heroes
	var brass := _mat(Color("b8892e"))
	brass.metallic = 0.7
	brass.roughness = 0.4
	var base := Vector3(0.52, TABLE_TOP, -0.52)
	_cylinder(0.11, 0.03, base + Vector3(0, 0.015, 0), brass)
	_cylinder(0.025, 0.42, base + Vector3(0, 0.24, 0), brass)
	_box(Vector3(0.46, 0.03, 0.03), base + Vector3(0, 0.38, 0), brass)
	for x: float in [-0.22, 0.0, 0.22]:
		var top := base + Vector3(x, 0.4 + (0.08 if x == 0.0 else 0.0), 0)
		_cylinder(0.04, 0.03, top, brass)
		_cylinder(0.026, 0.16, top + Vector3(0, 0.095, 0), _mat(Color("efe3c4")))
		var flame := _box(Vector3(0.024, 0.05, 0.024), top + Vector3(0, 0.2, 0), _mat(Color("ffc25a"), null, Vector3.ONE, true))
		flame.scale = Vector3(1, 1.2, 1)
	_flicker_light(base + Vector3(0, 0.75, 0.15), Color("ffa040"), 1.1, 2.6)
	# the pot: a pile of gold in the middle
	for k in 9:
		var pile := Node3D.new()
		var a := k * 2.4
		pile.position = POT + Vector3(cos(a) * 0.09 * (k % 3), TABLE_TOP + 0.01, sin(a) * 0.09 * (k % 3))
		viewport.add_child(pile)
		for n in randi_range(1, 5):
			_add_coin(pile)
	for k in 6:  # loose coins
		var c := _cylinder(0.045, 0.012, Vector3(randf_range(-0.7, 0.7), TABLE_TOP + 0.016, randf_range(-0.2, 0.75)), _coin_mat)
		c.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, 0)
	# mugs
	for p: Vector3 in [Vector3(-0.85, 0, 0.55), Vector3(0.9, 0, 0.5), Vector3(-0.55, 0, -0.85)]:
		_cylinder(0.065, 0.15, p + Vector3(0, TABLE_TOP + 0.075, 0), _mat(Color("7a4a26")))
		_cylinder(0.055, 0.01, p + Vector3(0, TABLE_TOP + 0.15, 0), _mat(Color("e8d6a0")))
	# dust drifting in the lamp light
	var dust := CPUParticles3D.new()
	dust.amount = 60
	dust.lifetime = 8.0
	dust.preprocess = 8.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.6, 0.9, 1.2)
	dust.position = Vector3(0, 1.6, 0)
	dust.direction = Vector3(0.2, 1, 0)
	dust.spread = 180
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.01
	dust.initial_velocity_max = 0.04
	var dot := QuadMesh.new()
	dot.size = Vector2(0.006, 0.006)
	var dm := _mat(Color(1.0, 0.85, 0.6, 0.5), null, Vector3.ONE, true)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	dust.mesh = dot
	viewport.add_child(dust)


func _flicker_light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	viewport.add_child(l)
	_flicker.append(l)
	_flicker_base.append(energy)
