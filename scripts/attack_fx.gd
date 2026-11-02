class_name AttackFx
extends RefCounted
## The characters' attack animations in the 3D tavern, by style (data/characters.json):
##   blood  (Demon Hunter)   Blood Slash: lunge and a red slash.     Soul Reap: a flurry of
##          slashes leaves glowing wounds; a second later the target bursts into red mist.
##   arcane (Arcane Knight)  Arcane Slash: a cyan crescent flies.    King's Verdict: a giant
##          blade of light chops straight down; the target splits top to bottom and the
##          halves slowly part, the cut charred.
##   thorn  (Verdant Ranger) Thorn Shot: a green arrow.              Final Arrow: an arrow shot
##          into the sky; a giant arrow falls through the target's head into the table.
##   flame  (Flame Dragon)   Inferno Claw: fiery claw streaks.       Dragon's Judgment: a narrow
##          high-pressure jet of fire; the target catches fire, chars black, then the
##          flames on it die down to smoke and embers.
## Your own attacks start from your hand in front of the camera; attacks on you end just in
## front of it (the table adds the screen effects). All times are multiplied by `k`
## (1 / game speed).

## Seconds from the start of an attack to the hit, and how long a finisher runs after it.
const IMPACT := {"blood": 0.5, "arcane": 0.55, "thorn": 0.45, "flame": 0.55}
## (Each covers its whole animation: the game waits this long before play goes on.)
const FINISH := {"blood": 2.8, "arcane": 2.6, "thorn": 2.8, "flame": 4.6}
## Soul Reap timing (x k): the slash flurry; short wounds while the body shudders; the
## wounds tear open; the burst a moment later.
const SLASHES_SECONDS := 0.55
const WOUND_SECONDS := 1.0
const TEAR_SECONDS := 0.3
## Dragon's Judgment timing (x k): a growl and an inhale, the jet, the target's own fire at
## full strength, then dying down; blackening runs while it burns.
const GROWL_SECONDS := 0.6  # the growl and the fiery inhale before the jet
const JET_SECONDS := 1.5
const BURN_FULL_SECONDS := 2.2
const BURN_FADE_SECONDS := 1.6
const CHAR_SECONDS := 1.6
const COLORS := {"blood": Color("ff2a3a"), "arcane": Color("6fe0ff"), "thorn": Color("8fff6a"), "flame": Color("ff8a2a")}

var tv: TavernView


func _init(view: TavernView) -> void:
	tv = view


## The normal attack from `a` to `t`, up to the moment it hits (returned, in seconds).
func normal(a: int, t: int, style: String, k: float) -> float:
	var impact: float = IMPACT[style] * k
	var from := tv._hand_point(a)
	var to := tv._body_point(t)
	var c := tv.character(a)
	var color: Color = COLORS[style]
	# a bot winds up first (Character3D.attack_pose): shots leave at the release, 60% of the
	# way to the hit; yours fly the whole time
	var release := impact * 0.6 if c else 0.0
	var flight := impact - release
	_normal_sounds(style, impact, release)
	match style:
		"blood":
			if c:
				# lunge most of the way to the target, slash, spring back
				var lunge := (to - c.global_position) * Vector3(1, 0, 1) * 0.45
				c.attack_pose(impact, lunge, to)
			else:
				_fly(_glow_quad(color, PixelTex.slash(0.6), 0.5), from, to, impact, 0.1)
			_after(impact, func() -> void: _slash(to, color, 0.7, 0.6, k))
		"arcane":
			if c:
				c.attack_pose(impact, Vector3.ZERO, to)
			_after(release, func() -> void:
				_fly(_glow_quad(color, PixelTex.slash(0.0), 0.55), tv._hand_point(a), to, flight, 0.05))
		"thorn":
			if c:
				c.attack_pose(impact, Vector3.ZERO, to)
			_after(release, func() -> void:
				_fly(_arrow(color, 1.0), tv._hand_point(a), to, flight, 0.08, true))
		"flame":
			if c:
				c.attack_pose(impact, Vector3.ZERO, to)
			_after(release, func() -> void:
				_fly(_glow_quad(color, PixelTex.glow(), 0.3), tv._hand_point(a), to, flight, 0.15))
			_after(impact, func() -> void:
				for i in 3:
					_slash(to + Vector3((i - 1) * 0.08, 0, 0.05), Color("ffb347"), 0.45, 1.3, k)
				_particles(to, Color("ffd23a"), Color("ff3a1a"), 24, 1.2, 0.5 * k, -1.0))
	return impact


## The finisher, from the moment the knockout attack lands; returns how long it runs.
func finisher(a: int, t: int, style: String, k: float) -> float:
	var to := tv._body_point(t)
	var victim := tv.character(t)
	var color: Color = COLORS[style]
	var killer := tv.character(a)
	if killer:
		killer.finisher_pose(k, to)  # the finisher's own arm moves, facing the target
	_finisher_sounds(style, k)
	match style:
		"blood":
			# Soul Reap: four quick slashes from every side, each leaving a short glowing wound;
			# the target shudders for a second, the wounds tear open, and 0.3 s later it
			# bursts into a cloud of red mist and pieces
			for i in 4:
				_after(i * 0.13 * k, func() -> void:
					_slash(to + Vector3(randf_range(-0.08, 0.08), randf_range(-0.1, 0.1), 0.05),
						color if i % 2 == 0 else Color("2a0a10").lightened(0.2), 0.9, [0.6, -0.6, 0.0, 1.57][i], k)
					if victim:
						victim.slash_mark(i))
			_after(SLASHES_SECONDS * k, func() -> void:
				if victim:
					victim.tremble(WOUND_SECONDS * k))
			_after((SLASHES_SECONDS + WOUND_SECONDS) * k, func() -> void:
				if victim:
					victim.open_wounds()
				_burst(to, color, 0.6, 0.25 * k))
			_after((SLASHES_SECONDS + WOUND_SECONDS + TEAR_SECONDS) * k, func() -> void:
				_particles(to, Color("ff2a3a"), Color("7a0010"), 160, 2.8, 1.0 * k, 3.0)  # spray
				_particles(to, Color(1.0, 0.15, 0.2, 0.9), Color(0.45, 0.0, 0.05), 120, 1.0, 1.8 * k, 0.4, 0.07)  # mist
				if victim:
					_pieces(victim.shatter(), to, k)
				_burst(to, color, 2.2, 0.5 * k))
		"arcane":
			# King's Verdict: a giant blade of light chops straight down through the middle
			var blade := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.03, 1.7, 0.55)  # thin side across, so it cuts left from right
			blade.mesh = box
			blade.material_override = tv._mat(Color("dffaff"), null, Vector3.ONE, true)
			tv.viewport.add_child(blade)
			blade.basis = Basis(Vector3.UP, victim.rotation.y if victim else 0.0)
			blade.position = to + Vector3(0, 1.7, 0)
			var bt := blade.create_tween()
			bt.tween_property(blade, "position", to - Vector3(0, 0.55, 0), 0.22 * k).set_ease(Tween.EASE_IN)
			bt.tween_property(blade, "transparency", 1.0, 0.35 * k)
			bt.tween_callback(blade.queue_free)
			_after(0.2 * k, func() -> void:
				_burst(to, Color.WHITE, 1.6, 0.35 * k)
				_particles(to, Color("ffb347"), Color("2a1a10"), 36, 0.6, 1.6 * k, -0.5)  # embers from the cut
				if victim:  # the halves part slowly
					victim.split(k))
		"thorn":
			# Final Arrow: one arrow up into the sky, then a giant one falls through the head
			var from := tv._hand_point(a)
			_after(0.31 * k, func() -> void:  # loosed when the bow, aimed at the sky, is drawn
				_fly(_arrow(color, 1.0), from + Vector3(0, 0.3, 0), from + Vector3(0, 3.5, -0.5), 0.4 * k, 0.0, true))
			# aim at where the head will be once pinned (slumped), so it ends up skewered
			var head := victim.head_point(true) if victim else to + Vector3(0, 0.25, 0)
			var pin := head.lerp(Vector3(0, TavernView.TABLE_TOP, 0), 0.35)  # into the table in front
			pin.y = TavernView.TABLE_TOP + 0.05
			var drop_from := head + (head - pin).normalized() * 2.6
			_after(0.8 * k, func() -> void:
				var giant := _arrow(color, 3.2)
				giant.position = drop_from
				tv.viewport.add_child(giant)
				giant.look_at(pin)
				var gt := giant.create_tween()
				gt.tween_property(giant, "position", pin + (drop_from - pin).normalized() * 0.55, 0.22 * k).set_ease(Tween.EASE_IN)
				gt.tween_callback(func() -> void:
					_particles(pin, Color("c8a070"), Color("6b4426"), 30, 1.0, 0.6 * k, 4.0)  # splinters
					_burst(head, color, 1.0, 0.3 * k)
					if victim:  # pinned on the spot; the colour drains away slowly
						victim.pinned(1.6 * k)))
		"flame":
			# Dragon's Judgment: a high-pressure jet of fire from the mouth. The target catches
			# fire at once and chars black; once black, the flames on it slowly die down.
			var dragon := tv.character(a)
			var from := tv._hand_point(a)
			if dragon:
				var forward := Basis(Vector3.UP, dragon.rotation.y) * Vector3(0, 0, 1)
				from = dragon.head_point() + forward * 0.3 * TavernView.CHARACTER_SCALE - Vector3(0, 0.06, 0)
			_after(GROWL_SECONDS * k, func() -> void: _flame_jet(from, to, JET_SECONDS * k))
			_after((GROWL_SECONDS + 0.12) * k, func() -> void:
				_body_fire(to, BURN_FULL_SECONDS * k, BURN_FADE_SECONDS * k)
				if victim:
					victim.burn(CHAR_SECONDS * k))
			_after((GROWL_SECONDS + 0.12 + BURN_FULL_SECONDS) * k, func() -> void:
				_particles(to + Vector3(0, 0.3, 0), Color(0.3, 0.27, 0.27, 0.8), Color(0.1, 0.08, 0.08), 50, 0.4, 3.0 * k, -0.5))  # smoke
	return FINISH[style] * k


# ---------- sound ----------

## Sounds the user picked in the sound lab (a slot left silent simply has no file).
## Normal attacks: sword as the blade lands (the knight's magic wave as it leaves), bow as
## the arrow leaves, the dragon's claw on the rake. Recordings start ~0.05 s before the hit.
func _normal_sounds(style: String, impact: float, release: float) -> void:
	match style:
		"blood", "arcane":
			_sfx("sword", maxf(0.0, impact - 0.05))
			if style == "arcane":
				_sfx("magic_wave", release)
		"thorn":
			_sfx("bow", release)
		"flame":
			_sfx("claw", release)


## Finishers: Soul Reap's slashes and burst; King's Verdict's chop; Final Arrow's sky shot and
## the giant arrow pinning the table; the dragon's roar, fire jet and the target burning.
func _finisher_sounds(style: String, k: float) -> void:
	match style:
		"blood":
			for i in 4:
				_sfx("sword", i * 0.13 * k, -2.0)
			_sfx("burst", (SLASHES_SECONDS + WOUND_SECONDS + TEAR_SECONDS) * k)
		"arcane":
			_sfx("sword", 0.15 * k, 2.0)
			_sfx("verdict", 0.2 * k)
		"thorn":
			_sfx("bow", 0.31 * k)
			_sfx("arrow_pin", 1.02 * k)
		"flame":
			_sfx("dragon_roar")
			_sfx("dragon_fire", GROWL_SECONDS * k)
			_sfx("burning", (GROWL_SECONDS + 0.12) * k, -3.0)


func _sfx(sound: String, delay := 0.0, volume_db := 0.0) -> void:
	tv._sound(sound, delay, volume_db)


# ---------- pieces ----------

func _after(seconds: float, f: Callable) -> void:
	if seconds <= 0.0:
		f.call()
	else:
		tv.get_tree().create_timer(seconds).timeout.connect(f)


## Move `node` (added to the room here) from `from` to `to` in `duration` with an arc of
## `height`, then remove it. `aim` turns it to point along the path (arrows).
func _fly(node: Node3D, from: Vector3, to: Vector3, duration: float, height: float, aim := false) -> void:
	node.position = from
	if node.get_parent() == null:
		tv.viewport.add_child(node)
	var last := [from]
	var step := func(s: float) -> void:
		var p := from.lerp(to, s) + Vector3(0, height * sin(PI * s), 0)
		if aim and p.distance_to(last[0]) > 0.001:
			node.look_at(p + (p - last[0]), Vector3.UP)
		last[0] = p
		node.position = p
	var t := node.create_tween()
	t.tween_method(step, 0.0, 1.0, duration)
	t.tween_callback(node.queue_free)


## A flat glowing picture that always faces the camera (slashes, fireballs).
func _glow_quad(color: Color, tex: Texture2D, size: float) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	q.mesh = mesh
	var m := tv._mat(color, tex, Vector3.ONE, true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q


## A slash mark at `at`: a crescent at `angle` that flashes in and fades.
func _slash(at: Vector3, color: Color, size: float, angle: float, k: float) -> void:
	var q := _glow_quad(color, PixelTex.slash(angle), size)
	q.position = at
	q.scale = Vector3.ONE * 0.6
	tv.viewport.add_child(q)
	var t := q.create_tween()
	t.tween_property(q, "scale", Vector3.ONE * 1.2, 0.12 * k)
	t.tween_property(q, "transparency", 1.0, 0.3 * k)
	t.tween_callback(q.queue_free)


func _burst(at: Vector3, color: Color, size: float, duration: float) -> void:
	var q := _glow_quad(color, PixelTex.glow(), size)
	q.position = at
	q.scale = Vector3.ONE * 0.3
	tv.viewport.add_child(q)
	var t := q.create_tween()
	t.tween_property(q, "scale", Vector3.ONE, duration).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(q, "transparency", 1.0, duration)
	t.tween_callback(q.queue_free)


## An arrow pointing along -Z (so look_at aims it): shaft, head and fletching.
func _arrow(color: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.5
	shaft.mesh = cyl
	shaft.rotation.x = PI / 2
	shaft.material_override = tv._mat(Color("8a6a3a"))
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.035
	cone.height = 0.09
	head.mesh = cone
	head.rotation.x = -PI / 2
	head.position = Vector3(0, 0, -0.29)
	head.material_override = tv._mat(color, null, Vector3.ONE, true)
	root.add_child(head)
	for side: float in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.005, 0.1)
		fin.mesh = box
		fin.position = Vector3(0, 0, 0.21)
		fin.rotation.z = side * 0.8
		fin.material_override = tv._mat(color.darkened(0.3))
		root.add_child(fin)
	root.scale = Vector3.ONE * scale
	return root


## A one-shot spray of little cubes (blood, embers, smoke, splinters) that rise or fall.
func _particles(at: Vector3, a: Color, b: Color, amount: int, speed: float, life: float, gravity: float,
		size := 0.035) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.amount = amount
	p.lifetime = maxf(life, 0.05)
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, a)
	ramp.set_color(1, Color(b, 0.0))
	p.color_ramp = ramp
	p.position = at
	tv.viewport.add_child(p)
	p.emitting = true
	tv.get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)


## Glowing flame cubes. `additive` brightens what is behind (the jet); without it the
## flames keep their own colour, so they still show on a charred black body.
func _fire_material(additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	return m


func _fire_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color("fffbe0"))
	ramp.add_point(0.25, Color("ffd23a"))
	ramp.add_point(0.6, Color("ff6a1a"))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.05, 0.02, 0.0))
	return ramp


## Dragon's Judgment: a narrow, very fast jet of fire like a pressure washer. A white-hot
## core beam that flickers, a tight spray of flame round it that widens a little towards the
## target, and fire splashing off where it hits. Runs `duration` seconds.
func _flame_jet(from: Vector3, to: Vector3, duration: float) -> void:
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	# core beam
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.05
	cyl.height = dist
	cyl.radial_segments = 10
	beam.mesh = cyl
	beam.material_override = tv._mat(Color("fff4c0"), null, Vector3.ONE, true)
	tv.viewport.add_child(beam)
	beam.position = from.lerp(to, 0.5)
	var axis := Basis(Quaternion(Vector3.UP, dir))  # the cylinder's axis (Y) along the jet
	var flicker := func(s: float) -> void:
		var w := 1.0 + 0.35 * sin(s * 90.0) * randf()
		beam.basis = axis * Basis.from_scale(Vector3(w, minf(1.0, s * 12.0), w))  # shoots out, then jitters
	var bt := beam.create_tween()
	bt.tween_method(flicker, 0.0, 1.0, duration)
	bt.tween_property(beam, "transparency", 1.0, 0.12)
	bt.tween_callback(beam.queue_free)
	# tight spray of flame along the beam
	var jet := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.05
	jet.mesh = mesh
	jet.material_override = _fire_material()
	var life := 0.2
	jet.amount = 320
	jet.lifetime = life
	jet.local_coords = false
	jet.direction = dir
	jet.spread = 2.5
	jet.initial_velocity_min = dist / life * 0.95
	jet.initial_velocity_max = dist / life * 1.1
	jet.gravity = Vector3.ZERO
	jet.scale_amount_min = 0.7
	jet.scale_amount_max = 1.4
	var grow := Curve.new()  # thin at the mouth, fatter where it hits
	grow.max_value = 3.0
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 2.4))
	jet.scale_amount_curve = grow
	jet.color_ramp = _fire_ramp()
	jet.position = from
	tv.viewport.add_child(jet)
	jet.emitting = true
	# fire splashing back and out where it hits
	var splash := CPUParticles3D.new()
	var smesh := BoxMesh.new()
	smesh.size = Vector3.ONE * 0.06
	splash.mesh = smesh
	splash.material_override = _fire_material()
	splash.amount = 120
	splash.lifetime = 0.35
	splash.local_coords = false
	splash.direction = -dir + Vector3.UP * 0.4
	splash.spread = 75.0
	splash.initial_velocity_min = 0.8
	splash.initial_velocity_max = 2.2
	splash.gravity = Vector3(0, 1.0, 0)
	splash.color_ramp = _fire_ramp()
	splash.position = to
	tv.viewport.add_child(splash)
	splash.emitting = true
	_after(duration, func() -> void:
		jet.emitting = false
		splash.emitting = false)
	tv.get_tree().create_timer(duration + 0.6).timeout.connect(func() -> void:
		jet.queue_free()
		splash.queue_free())


## The target on fire: flames rising all over its body at full strength for `full` seconds,
## then dying down over `fade` seconds, with embers drifting up as they go.
func _body_fire(at: Vector3, full: float, fade: float) -> void:
	var fire := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.09
	fire.mesh = mesh
	fire.material_override = _fire_material(false)
	fire.amount = 220
	fire.lifetime = 0.8
	fire.local_coords = false
	# a thin sheet over the front of the body (the side you see), not inside it
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(0.3, 0.45, 0.06) * TavernView.CHARACTER_SCALE
	fire.direction = Vector3.UP
	fire.spread = 18.0
	fire.initial_velocity_min = 0.4
	fire.initial_velocity_max = 1.0
	fire.gravity = Vector3(0, 1.4, 0)
	fire.scale_amount_min = 0.8
	fire.scale_amount_max = 1.8
	var shrink := Curve.new()  # each flame shrinks as it rises
	shrink.add_point(Vector2(0, 1.0))
	shrink.add_point(Vector2(0.6, 0.8))
	shrink.add_point(Vector2(1, 0.25))
	fire.scale_amount_curve = shrink
	fire.color_ramp = _fire_ramp()
	var to_cam := (tv._camera.global_position - at) * Vector3(1, 0, 1)
	fire.position = at + Vector3(0, 0.05, 0) + to_cam.normalized() * 0.42  # just clear of the big head
	fire.basis = Basis(Vector3.UP, atan2(to_cam.x, to_cam.z))  # the sheet faces the camera
	tv.viewport.add_child(fire)
	fire.emitting = true
	var t := fire.create_tween()
	t.tween_interval(full)
	var die_down := func(s: float) -> void:  # the flames shrink and slow until they're gone
		fire.scale_amount_min = lerpf(0.8, 0.02, s)
		fire.scale_amount_max = lerpf(1.8, 0.05, s)
		fire.initial_velocity_max = lerpf(1.0, 0.3, s)
	t.tween_method(die_down, 0.0, 1.0, fade)
	t.tween_callback(func() -> void: fire.emitting = false)
	t.tween_interval(fire.lifetime + 0.2)
	t.tween_callback(fire.queue_free)
	_after(full, func() -> void:
		_particles(at, Color("ffb347"), Color("ff3a1a"), 30, 0.5, fade + 0.5, -0.7))  # embers


## Soul Reap: the shattered body as chunks in its colours, flung out and left lying on the
## table or the floor.
func _pieces(colors: Array[Color], at: Vector3, k: float) -> void:
	for i in 16:
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * randf_range(0.05, 0.11)
		chunk.mesh = box
		chunk.material_override = tv._mat(colors[i % colors.size()])
		chunk.position = at + Vector3(randf_range(-0.12, 0.12), randf_range(-0.2, 0.2), randf_range(-0.1, 0.1))
		tv.viewport.add_child(chunk)
		var out := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.3, 0.9)
		var land := chunk.position + out
		var on_table := Vector2(land.x, land.z).length() < TavernView.TABLE_RADIUS - 0.1
		land.y = (TavernView.TABLE_TOP + 0.03 if on_table else 0.04)
		var start := chunk.position
		var spin := Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		var arc := func(s: float) -> void:
			chunk.position = start.lerp(land, s) + Vector3(0, 0.5 * sin(PI * s), 0)
			chunk.rotation = spin * s
		chunk.create_tween().tween_method(arc, 0.0, 1.0, randf_range(0.5, 0.8) * k)
