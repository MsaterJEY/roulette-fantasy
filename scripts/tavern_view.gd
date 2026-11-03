class_name TavernView
extends SubViewportContainer
## First-person 3D tavern behind the 2D HUD: round felt table, three bots on chairs,
## candles, props and three dice. Rendered at the full screen size with anti-aliasing;
## the blocky look comes from the models and the nearest-filtered pixel textures.
## Everything is built in code from simple meshes, the bots too (Character3D: the chosen heroes, set up by setup_characters() once you have
## picked yours). While you pick a target, the bots you may pick glow orange and can be
## clicked (seat_at()). Attacks and finishers are animated by AttackFx.

const RENDER_SIZE := Vector2i(960, 540)
const TARGET_GLOW := Color(1.6, 0.85, 0.45)
const CARD_FLIGHT := 0.55  # seconds a played card flies from hand to target
const CARD_SIZE := Vector3(0.16, 0.22, 0.012)
## Where your hand is / where things aimed at you arrive (just in front of the camera).
const YOUR_HAND := Vector3(0, 1.05, 1.35)
const YOU := Vector3(0, 1.3, 1.15)
const TABLE_TOP := 0.76
const TABLE_RADIUS := 1.25
## Places round the table (you, left, top, right) ...
const SEAT_POS := [Vector3(0, 0, 1.9), Vector3(-1.5, 0, -0.4), Vector3(0, 0, -1.5), Vector3(1.5, 0, -0.4)]
## ... and which of them each seat takes for 2, 3 or 4 players (you always at the camera).
const LAYOUTS := {2: [0, 2], 3: [0, 1, 3], 4: [0, 1, 2, 3]}
## 5 or 6 players: the bots sit on an arc round the far side, left to right, at these
## angles (degrees round the table from your seat) and BOT_RING metres from the middle.
const ARC_LAYOUTS := {5: [-108.0, -152.0, 152.0, 108.0], 6: [-106.0, -143.0, 180.0, 143.0, 106.0]}
const BOT_RING := 1.55
const CHARACTER_HEIGHT := 0.9  # metres from the seat to the top of the head
const CHARACTER_SCALE := 1.15
## Bots face a point between the table centre and you, so you see their faces, not profiles.
const LOOK_AT := Vector3(0, 0, 1.0)
const DIE_SIZE := 0.13

var viewport: SubViewport
var dice: Array[Dice3D] = []
var _characters: Array[Character3D] = [null]  # by seat; you (0) have no body
var seat_pos: Array[Vector3] = []  # where each seat sits, set by setup_characters()
var fx: AttackFx
var sfx: Sfx  # set by the table; the attacks and dice play their sounds through it
var _ko_pending: Dictionary = {}  # seat -> true while its knockout pose waits for a finisher
var _glow: MeshInstance3D
## Per bot seat: effect icons above the head, the coloured aura behind, and the look the
## sprite returns to after a hit flash.
var _status_rows: Array[Node3D] = []
var _auras: Array[MeshInstance3D] = []
var _base_modulate: Array[Color] = []
var _time := 0.0
var _camera: Camera3D
var _targetable: Dictionary = {}  # seat -> true while it can be picked as a target
var _hover := -1  # targetable bot under the mouse
const ICON_SIZE := 0.16  # metres, effect icons over the bots' heads
const HEAD_Y := 1.2  # head height of a seated bot


func _ready() -> void:
	stretch = true
	stretch_shrink = 1  # full resolution: crisp edges (the pixel look is in the textures)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	_build_environment()
	_build_room()
	_build_table()
	_build_props()
	_build_dice()
	fx = AttackFx.new(self)
	_camera = Camera3D.new()
	_camera.fov = 60
	viewport.add_child(_camera)
	_camera.position = Vector3(0, 1.75, 2.2)
	_camera.look_at(Vector3(0, 0.7, -0.45))


# ---------- public ----------

## Seat the heroes: `ids[seat]` is the character id of each seat (seat 0, you, gets no body);
## 2-6 seats, placed by LAYOUTS / ARC_LAYOUTS. Builds their chairs, lights and effect markers too.
func setup_characters(ids: Array) -> void:
	seat_pos.clear()
	var n := clampi(ids.size(), 2, 6)
	if n <= 4:
		for place: int in LAYOUTS[n]:
			seat_pos.append(SEAT_POS[place])
	else:
		seat_pos.append(SEAT_POS[0])
		for deg: float in ARC_LAYOUTS[n]:
			var a := deg_to_rad(deg)
			seat_pos.append(Vector3(sin(a), 0, cos(a)) * BOT_RING)
	_build_seats()
	for seat in range(1, seat_pos.size()):
		_characters.append(null)
		var p: Vector3 = seat_pos[seat]
		var facing := LOOK_AT - Vector3(p.x, 0, p.z)
		var s := Character3D.new(ids[seat])
		s.position = p
		s.rotation.y = atan2(facing.x, facing.z)
		s.scale = Vector3.ONE * CHARACTER_SCALE
		viewport.add_child(s)
		_characters[seat] = s


## A player is out: the cards they held fall from their hands and scatter, face down, on
## the table in front of them (yours fall in front of the camera). `count`: how many.
func drop_cards(seat: int, count: int, k: float) -> void:
	var c := character(seat)
	if c:
		c.drop_cards()
	var from := _hand_point(seat)
	var spot: Vector3 = seat_pos[seat] * 0.5  # on the felt, in front of their seat
	for i in count:
		var card := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 0.012, 0.22)  # lying flat
		card.mesh = box
		card.material_override = _mat(Color("27306b"))
		var inner := MeshInstance3D.new()
		var ibox := BoxMesh.new()
		ibox.size = Vector3(0.1, 0.014, 0.15)
		inner.mesh = ibox
		inner.material_override = _mat(Color("d6b048").darkened(0.3))
		card.add_child(inner)
		viewport.add_child(card)
		var land := spot + Vector3(randf_range(-0.28, 0.28), 0, randf_range(-0.2, 0.2))
		land.y = TABLE_TOP + 0.012 + i * 0.004
		var start := from + Vector3(randf_range(-0.08, 0.08), 0, 0)
		var tumble := Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
		var yaw := randf() * TAU
		var fall := func(s: float) -> void:
			card.position = start.lerp(land, s) + Vector3(0, 0.25 * sin(PI * s), 0)
			card.rotation = tumble * (1.0 - s) + Vector3(0, yaw, 0) * s
		var t := card.create_tween()
		t.tween_interval(i * 0.06 * k)
		t.tween_method(fall, 0.0, 1.0, randf_range(0.45, 0.65) * k).set_ease(Tween.EASE_IN)


func _sound(sound: String, delay := 0.0, volume_db := 0.0) -> void:
	if sfx:
		sfx.play(sound, delay, volume_db)


## A camera shake of `strength` (view units) dying away over `seconds`. Uses the lens offset,
## so it adds to whatever the camera is doing (the death-camera glide).
func shake(strength: float, seconds: float) -> void:
	var t := create_tween()
	var jitter := func(s: float) -> void:
		var a := strength * (1.0 - s)
		_camera.h_offset = randf_range(-a, a)
		_camera.v_offset = randf_range(-a, a)
	t.tween_method(jitter, 0.0, 1.0, seconds)
	t.tween_callback(func() -> void:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0)


## The hero at `seat`. You (seat 0) have none, except while your own knockout plays
## (watch_your_death()).
func character(seat: int) -> Character3D:
	return _characters[seat] if seat >= 0 and seat < _characters.size() else null


## Where the camera goes to watch your own knockout: high over the far side of the felt,
## above everyone's heads, looking back down at your seat; seconds to glide there and back.
const DEATH_CAM := Vector3(0.0, 2.9, -0.2)
const DEATH_FOV := 40.0  # narrower than the table view: you fill the shot, not the bots beside you
const DEATH_GLIDE_OUT := 0.45
const DEATH_GLIDE_BACK := 0.7


## You are being knocked out: your hero (`character_id`) appears in your seat and the camera
## pulls out over the table to watch the finisher for `seconds`, then glides back to your
## first-person view and your body is gone again. Times x `k`.
func watch_your_death(character_id: String, seconds: float, k: float) -> void:
	if _characters[0] != null:
		return
	var p: Vector3 = seat_pos[0]
	var facing := -Vector3(p.x, 0, p.z)
	var chair := _chair(p, facing, _mat(Color("4a2f1c")))
	var you := Character3D.new(character_id)
	you.position = p
	you.rotation.y = atan2(facing.x, facing.z)
	you.scale = Vector3.ONE * CHARACTER_SCALE
	viewport.add_child(you)
	_characters[0] = you
	var before := viewport.get_child_count()  # what the finisher leaves at your seat comes after
	var home := _camera.transform
	var home_fov := _camera.fov
	var shot := Transform3D(Basis.looking_at(p + Vector3(0, 0.95, 0) - DEATH_CAM), DEATH_CAM)
	var glide := func(from: Transform3D, to: Transform3D) -> Callable:
		var fov_from := home_fov if from == home else DEATH_FOV
		var fov_to := DEATH_FOV if from == home else home_fov
		return func(f: float) -> void:
			_camera.transform = from.interpolate_with(to, f)
			_camera.fov = lerpf(fov_from, fov_to, f)
	var t := create_tween()
	t.tween_method(glide.call(home, shot), 0.0, 1.0, DEATH_GLIDE_OUT * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(maxf(seconds, 0.0))
	t.tween_callback(func() -> void:  # gone before the camera passes back over your seat
		you.visible = false
		for n in chair:
			n.visible = false)
	t.tween_method(glide.call(shot, home), 0.0, 1.0, DEATH_GLIDE_BACK * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:  # back in your own eyes: nothing of you in the way
		_characters[0] = null
		you.queue_free()
		for n in chair:
			n.queue_free()
		# nor what the finisher left there (the giant arrow, pieces) right in front of the camera
		for i in range(before, viewport.get_child_count()):
			var n := viewport.get_child(i) as Node3D
			if n and (n.has_meta("leftover") or Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < 0.9):
				n.queue_free())


## `attacker`'s character attack on `target`; returns the seconds until it hits. A finisher
## (the hit knocks the target out) follows on from the hit; finisher_time() says how long.
func play_attack(attacker: int, target: int, style: String, finisher: bool, k: float) -> float:
	var impact := fx.normal(attacker, target, style, k)
	if finisher:
		fx._after(impact, func() -> void: fx.finisher(attacker, target, style, k))
	return impact


func finisher_time(style: String, k: float) -> float:
	return AttackFx.FINISH[style] * k

## The bot whose body is at `screen_pos` (this view's coordinates), or -1. Checks a box
## round each character from its seat to the top of its head, as seen by the camera.
func seat_at(screen_pos: Vector2) -> int:
	var shrink := float(stretch_shrink)
	for seat in range(1, _characters.size()):
		var c := _characters[seat]
		if c == null or not c.visible:
			continue
		var foot := _camera.unproject_position(c.global_position + Vector3(0, 0.5 * CHARACTER_SCALE, 0)) * shrink
		var top := _camera.unproject_position(c.global_position + Vector3(0, 1.5 * CHARACTER_SCALE, 0)) * shrink
		var h := absf(foot.y - top.y)
		if Rect2(top.x - h * 0.45, top.y, h * 0.9, h).has_point(screen_pos):
			return seat
	return -1


## A played card flies from `from_seat`'s hand to `to_seat` in an arc, spinning, and bursts
## in its type's colour on arrival. A card played on yourself rises and bursts above you.
func throw_card(from_seat: int, to_seat: int, card: Dictionary, duration: float) -> void:
	var start := _hand_point(from_seat)
	var end := _body_point(to_seat) + (Vector3(0, 0.45, 0) if from_seat == to_seat else Vector3.ZERO)
	var c := _make_card(card)
	c.position = start
	viewport.add_child(c)
	var spin := randf_range(1.5, 2.5) * TAU * (1.0 if randf() < 0.5 else -1.0)
	var t := c.create_tween()
	var fly := func(k: float) -> void:
		c.position = start.lerp(end, k) + Vector3(0, 0.35 * sin(PI * k), 0)
		c.rotation = Vector3(-0.4, spin * k, 0.25 * sin(TAU * k))
	t.tween_method(fly, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(c, "scale", Vector3.ONE * 0.1, 0.12)
	t.tween_callback(func() -> void:
		_burst(end, UiStyle.TYPE_COLORS.get(card["type"], UiStyle.BRASS))
		c.queue_free())


func _hand_point(seat: int) -> Vector3:
	if character(seat) == null:
		return YOUR_HAND
	var c := _characters[seat]
	var forward := Basis(Vector3.UP, c.rotation.y) * Vector3(0, 0, 1)
	return c.global_position + Vector3(0, 0.9 * CHARACTER_SCALE, 0) + forward * 0.35 * CHARACTER_SCALE


func _body_point(seat: int) -> Vector3:
	if character(seat) == null:
		return YOU
	return _characters[seat].global_position + Vector3(0, 1.05 * CHARACTER_SCALE, 0)


## A small 3D card: body in the type's colour, the card's picture on the front.
func _make_card(card: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = CARD_SIZE
	body.mesh = box
	body.material_override = _mat(UiStyle.TYPE_COLORS.get(card["type"], UiStyle.BRASS).darkened(0.15))
	root.add_child(body)
	for side: float in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.12, 0.12)
		face.mesh = quad
		var m := _mat(Color.WHITE, Icons.get_icon(card["id"]))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.material_override = m
		face.position = Vector3(0, 0.01, side * (CARD_SIZE.z / 2 + 0.002))
		face.rotation.y = 0.0 if side > 0 else PI
		root.add_child(face)
	return root


func _burst(at: Vector3, color: Color) -> void:
	var glow := _quad(Vector2(0.5, 0.5), _mat(color.lightened(0.3), PixelTex.glow(), Vector3.ONE, true))
	(glow.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.position = at
	glow.scale = Vector3.ONE * 0.3
	var t := glow.create_tween()
	t.tween_property(glow, "scale", Vector3.ONE * 1.6, 0.35).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(glow, "transparency", 1.0, 0.35)
	t.tween_callback(glow.queue_free)


## While targeting: which bots may be picked (they glow orange), and which one the mouse is on
## (it glows brighter).
func set_targetable(seat: int, on: bool) -> void:
	if on:
		_targetable[seat] = true
	else:
		_targetable.erase(seat)
		var c := character(seat)
		if c and not c.destroyed:  # a body a finisher burnt/cut keeps its look
			c.modulate = _base_modulate[seat]


func set_hover(seat: int) -> void:
	_hover = seat if _targetable.has(seat) else -1


## Toss the three dice from `seat` onto the table so they land showing `values`.
func throw_dice(seat: int, values: Array[int], duration: float) -> void:
	_sound("dice")
	var from: Vector3 = seat_pos[seat] * 0.62 + Vector3(0, 1.05, 0)
	for i in 3:
		var land := Vector3((i - 1) * 0.2 + randf_range(-0.03, 0.03), TABLE_TOP + DIE_SIZE / 2,
			0.05 + randf_range(-0.05, 0.05))
		dice[i].toss(from + Vector3(randf_range(-0.1, 0.1), 0, 0), land, values[i], duration * randf_range(0.85, 1.0))
	var t := _glow.create_tween()
	t.tween_property(_glow, "transparency", 0.0, duration * 0.6)
	t.tween_property(_glow, "transparency", 0.55, 0.8)


## Whose turn it is (that bot is lit up), who is out (grey and slumped) and the effects on
## them: one icon each over the head, and a purple (curse) or blue (good effect) aura.
## `ko_delay`: seconds to wait before showing the knockout (a finisher is still playing).
func set_seat_state(seat: int, active: bool, alive: bool, statuses: Dictionary = {}, ko_delay := 0.0) -> void:
	var s := character(seat)
	if s == null or seat == 0:  # your body only exists while your knockout plays
		return
	if not alive:
		if ko_delay > 0.0 and not _ko_pending.has(seat):
			_ko_pending[seat] = true
			get_tree().create_timer(ko_delay).timeout.connect(func() -> void:
				_ko_pending.erase(seat)
				_show_knocked_out(seat))
		elif not _ko_pending.has(seat):
			_show_knocked_out(seat)
	else:
		_base_modulate[seat] = Color(1.15, 1.1, 1.0) if active else Color(0.85, 0.85, 0.85)
		s.rotation.x = 0.0
		s.set_knocked_out(false)
		s.modulate = _base_modulate[seat]
	var row := _status_rows[seat]
	for child in row.get_children():
		child.queue_free()
	var ids: Array = statuses.keys()
	for i in ids.size():
		var icon := _icon_sprite(ids[i])
		icon.position = Vector3(0, -(i - (ids.size() - 1) / 2.0) * (ICON_SIZE + 0.03), 0)
		row.add_child(icon)
		icon.add_child(_count_label(int(statuses[ids[i]])))
	var cursed := ids.any(func(id: String) -> bool: return not id in GameController.BUFFS)
	var aura := _auras[seat]
	aura.visible = alive and not ids.is_empty()
	(aura.material_override as StandardMaterial3D).albedo_color = Color("b25cff") if cursed else Color("4fa3ff")


## Out of the game: grey, slumped over the table, x x eyes. A body a finisher broke (cut,
## shattered, burnt) stays as the finisher left it.
func _show_knocked_out(seat: int) -> void:
	var s := character(seat)
	s.set_knocked_out(true)
	if s.destroyed:
		return
	_base_modulate[seat] = Character3D.KO_TINT
	s.modulate = _base_modulate[seat]
	s.rotation.x = Character3D.SLUMP


## An attack on a bot landed: the picture flashes red and shakes, "-1" floats up.
func hit(seat: int) -> void:
	var s := character(seat)
	if s == null:
		return
	s.hurt()
	var home: Vector3 = seat_pos[seat]
	var t := s.create_tween()
	t.tween_property(s, "modulate", Color(2.0, 0.4, 0.4), 0.06)
	for dx: float in [-0.06, 0.06, -0.04, 0.04, 0.0]:
		t.tween_property(s, "position", home + Vector3(dx, 0, 0), 0.05)
	t.tween_property(s, "modulate", _base_modulate[seat], 0.25)
	var label := Label3D.new()
	label.text = "-1"
	label.font_size = 48
	label.outline_size = 12
	label.modulate = Color("ff5a4f")
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = seat_pos[seat] + Vector3(0, 0.42 + CHARACTER_HEIGHT * 0.75, 0.1)
	viewport.add_child(label)
	var lt := label.create_tween()
	lt.tween_property(label, "position:y", label.position.y + 0.3, 0.9).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	lt.tween_callback(label.queue_free)


## A bot blocked with a Defense card: a shield pops up in front of it.
func block(seat: int) -> void:
	var s := character(seat)
	if s == null:
		return
	var shield := _icon_sprite("defense")
	shield.pixel_size = 0.4 / 16.0
	var toward_cam: Vector3 = (Vector3(0, 0, 2.2) - seat_pos[seat]).normalized()
	shield.position = seat_pos[seat] + Vector3(0, 0.42 + CHARACTER_HEIGHT * 0.45, 0) + toward_cam * 0.15
	shield.scale = Vector3.ONE * 0.3
	viewport.add_child(shield)
	var t := shield.create_tween()
	t.tween_property(shield, "scale", Vector3.ONE * 1.2, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(shield, "scale", Vector3.ONE, 0.1)
	t.tween_interval(0.5)
	t.tween_property(shield, "modulate:a", 0.0, 0.35)
	t.tween_callback(shield.queue_free)
	var ft := s.create_tween()
	ft.tween_property(s, "modulate", Color(0.7, 1.2, 2.0), 0.08)
	ft.tween_property(s, "modulate", _base_modulate[seat], 0.4)


## The count on an effect icon over a bot's head (turns left, or stacks), at its corner.
func _count_label(n: int) -> Label3D:
	var l := Label3D.new()
	l.text = str(n)
	l.font_size = 40
	l.outline_size = 12
	l.pixel_size = 0.0022
	l.position = Vector3(ICON_SIZE * 0.42, -ICON_SIZE * 0.3, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 11
	l.outline_render_priority = 10
	return l


func _icon_sprite(id: String) -> Sprite3D:
	var icon := Sprite3D.new()
	icon.texture = Icons.get_icon(id)
	icon.pixel_size = ICON_SIZE / 16.0
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	icon.shaded = false
	icon.no_depth_test = true  # always readable, even over the table edge
	icon.render_priority = 10
	return icon


func _process(delta: float) -> void:
	_time += delta
	for seat: int in _targetable:
		if character(seat):
			var glow := 0.75 if seat == _hover else 0.3 + 0.15 * sin(_time * 6.0)
			_characters[seat].modulate = _base_modulate[seat].lerp(TARGET_GLOW, glow)
	# auras breathe slowly
	for aura in _auras:
		if aura and aura.visible:
			aura.transparency = 0.35 + 0.2 * sin(_time * 3.0)


# ---------- building ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("120c09")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6b4a33")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	# warm lamp over the table
	_light(Vector3(0, 2.4, 0.2), Color("ffc27a"), 1.6, 4.5)


func _build_room() -> void:
	var floor_mat := _mat(Color.WHITE, PixelTex.planks(Color("4a2f1c"), Color("3a2414")), Vector3(8, 8, 1))
	_box(Vector3(12, 0.1, 12), Vector3(0, -0.05, 0), floor_mat)
	var wall_mat := _mat(Color.WHITE, PixelTex.bricks(Color("3b2a22"), Color("2a1d17")), Vector3(6, 2, 1))
	_box(Vector3(9, 3.4, 0.2), Vector3(0, 1.7, -3.2), wall_mat)
	_box(Vector3(0.2, 3.4, 7), Vector3(-3.6, 1.7, -0.2), wall_mat)
	_box(Vector3(0.2, 3.4, 7), Vector3(3.6, 1.7, -0.2), wall_mat)
	var wood := _mat(Color("5a3a22"))
	# beams and shelves with candles
	_box(Vector3(9, 0.18, 0.25), Vector3(0, 2.9, -3.0), wood)
	for x: float in [-2.4, 2.4]:
		_box(Vector3(1.3, 0.06, 0.3), Vector3(x, 1.55, -3.0), wood)
		for k in 3:
			_candle(Vector3(x - 0.4 + k * 0.4, 1.58, -2.95), k == 1)
	# banners behind the top seat
	var banner_tex := PixelTex.banner(Color("3d2a6b"), Color("d6b048"))
	for x: float in [-1.1, 1.1]:
		var q := _quad(Vector2(0.6, 1.1), _mat(Color.WHITE, banner_tex))
		q.position = Vector3(x, 1.9, -3.08)
	# side candles near the bots
	_candle(Vector3(-3.4, 1.2, -1.2), true)
	_candle(Vector3(3.4, 1.2, -1.2), true)
	# barrels in the corners
	var barrel := _mat(Color("6b4426"))
	for p: Vector3 in [Vector3(-2.8, 0.45, -2.5), Vector3(2.9, 0.45, -2.4), Vector3(-3.0, 0.45, 1.0)]:
		_cylinder(0.35, 0.9, p, barrel)


func _build_table() -> void:
	_cylinder(0.25, 0.7, Vector3(0, 0.35, 0), _mat(Color("3a2414")))
	_cylinder(TABLE_RADIUS, 0.12, Vector3(0, TABLE_TOP - 0.06, 0), _mat(Color("6b4426")))
	var felt := _mat(Color.WHITE, PixelTex.felt(Color("1f5a38"), Color("184a2d"), Color("c9a227")))
	_cylinder(TABLE_RADIUS - 0.1, 0.02, Vector3(0, TABLE_TOP, 0), felt)
	# glowing ring under the dice; brightens while they roll
	_glow = _quad(Vector2(0.75, 0.75), _mat(Color("ffd76a"), PixelTex.ring(), Vector3.ONE, true))
	_glow.rotation.x = -PI / 2
	_glow.position = Vector3(0, TABLE_TOP + 0.012, 0.05)
	_glow.transparency = 0.55


func _build_seats() -> void:
	var chair := _mat(Color("4a2f1c"))
	_status_rows.append(null)  # seat 0 is you (the camera)
	_auras.append(null)
	_base_modulate.append(Color.WHITE)
	var card_back := _mat(Color("27306b"))
	var gold := _mat(Color("d6a63a"))
	for seat in range(1, seat_pos.size()):
		var p: Vector3 = seat_pos[seat]
		var away := Vector3(p.x, 0, p.z).normalized()
		# their cards and coins on the felt in front of them
		var toward := -away
		var spot := p * 0.55 + Vector3(0, TABLE_TOP + 0.02, 0)
		var side := toward.cross(Vector3.UP) * 0.28
		_box(Vector3(0.16, 0.04, 0.22), spot + side, card_back, atan2(toward.x, toward.z) + 0.3)
		for k in 3:
			_cylinder(0.045, 0.012, spot - side + Vector3(0, k * 0.014, 0), gold)
		var facing := LOOK_AT - Vector3(p.x, 0, p.z)
		# chair straight behind the bot (it sits turned towards you, not the centre)
		_chair(p, facing, chair)
		# warm fill light in front of each bot so faces read in the dim room
		_light(p - away * 0.7 + Vector3(0, 1.3, 0), Color("ffd2a0"), 0.6, 1.6)
		_base_modulate.append(Color.WHITE)
		var row := Node3D.new()
		# a column beside the head, on the table-centre side (seat panels sit above the bots;
		# the top bot's on its right)
		row.position = p + Vector3(-signf(p.x) * 0.5 if absf(p.x) > 0.5 else 0.45, HEAD_Y - 0.1, 0.1)
		viewport.add_child(row)
		_status_rows.append(row)
		# aura: a soft glow just behind the picture
		var aura := _quad(Vector2(1.0, 1.25), _mat(Color.WHITE, PixelTex.glow(), Vector3.ONE, true))
		(aura.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		aura.position = p + Vector3(0, 0.42 + CHARACTER_HEIGHT / 2, 0) + Vector3(p.x, 0, p.z).normalized() * 0.08
		aura.visible = false
		_auras.append(aura)


func _build_props() -> void:
	var card_back := _mat(Color("27306b"))
	var gold := _mat(Color("d6a63a"))
	# mug and lantern
	_cylinder(0.07, 0.16, Vector3(-0.85, TABLE_TOP + 0.08, -0.55), _mat(Color("7a4a26")))
	# lantern further from the elf, so its face isn't washed out
	_box(Vector3(0.14, 0.24, 0.14), Vector3(0.55, TABLE_TOP + 0.12, -0.85), _mat(Color("2a2a2a")))
	_box(Vector3(0.09, 0.14, 0.09), Vector3(0.55, TABLE_TOP + 0.12, -0.85), _mat(Color("ffcf6a"), null, Vector3.ONE, true))
	_light(Vector3(0.55, TABLE_TOP + 0.3, -0.85), Color("ffb347"), 0.6, 1.8)
	# stray cards and coins on the felt
	_box(Vector3(0.16, 0.01, 0.22), Vector3(-0.5, TABLE_TOP + 0.015, 0.45), card_back, 0.6)
	_box(Vector3(0.16, 0.01, 0.22), Vector3(0.55, TABLE_TOP + 0.015, 0.4), card_back, -0.4)
	_cylinder(0.045, 0.012, Vector3(-0.3, TABLE_TOP + 0.016, 0.7), gold)
	_cylinder(0.045, 0.012, Vector3(0.35, TABLE_TOP + 0.016, 0.75), gold)


func _build_dice() -> void:
	for i in 3:
		var d := Dice3D.new(DIE_SIZE)
		viewport.add_child(d)
		d.position = Vector3((i - 1) * 0.2, TABLE_TOP + DIE_SIZE / 2, 0.05)
		d.show_value(i * 2 + 1)
		dice.append(d)


# ---------- small helpers ----------

func _mat(color: Color, tex: Texture2D = null, uv_scale := Vector3.ONE, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = tex
	m.uv1_scale = uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 1.0
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


func _box(box_size: Vector3, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	return _add(mesh, pos, m, yaw)


func _cylinder(radius: float, height: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	return _add(mesh, pos, m)


func _quad(quad_size: Vector2, m: Material) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	return _add(mesh, Vector3.ZERO, m)


func _add(mesh: Mesh, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(mi)
	return mi


func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	viewport.add_child(l)


## A chair for a hero seated at `p` facing `facing`: a tall back, the seat under the thighs
## and four legs.
func _chair(p: Vector3, facing: Vector3, m: Material) -> Array[MeshInstance3D]:
	var f := facing.normalized()
	var r := f.cross(Vector3.UP)
	var yaw := atan2(f.x, f.z)
	var parts: Array[MeshInstance3D] = []
	parts.append(_box(Vector3(0.75, 1.3, 0.1), p - f * 0.4 + Vector3(0, 0.65, 0), m, yaw))
	var seat := p + f * 0.02
	parts.append(_box(Vector3(0.6, 0.06, 0.62), seat + Vector3(0, 0.45, 0), m, yaw))
	for c: Vector3 in [r * 0.26 + f * 0.26, -r * 0.26 + f * 0.26, r * 0.26 - f * 0.26, -r * 0.26 - f * 0.26]:
		parts.append(_box(Vector3(0.06, 0.42, 0.06), seat + c + Vector3(0, 0.21, 0), m, yaw))
	return parts


func _candle(pos: Vector3, with_light: bool) -> void:
	_cylinder(0.035, 0.14, pos + Vector3(0, 0.07, 0), _mat(Color("efe3c4")))
	_box(Vector3(0.03, 0.05, 0.03), pos + Vector3(0, 0.17, 0), _mat(Color("ffb347"), null, Vector3.ONE, true))
	if with_light:
		_light(pos + Vector3(0, 0.3, 0.2), Color("ff9a3c"), 0.7, 2.4)
