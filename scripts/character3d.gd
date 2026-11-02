class_name Character3D
extends Node3D
## A blocky 3D chibi hero built from boxes and cones (no model files): one of the four
## characters in data/characters.json. Lower body, upper body (torso, arms, a fan of cards,
## the big head with a pixel face) and the character's weapon. Front = +Z; the tavern turns
## it to face the table. `modulate` tints every part (hit flash, dimmed when it's not their
## turn, grey when knocked out). Breathes, looks around and blinks while idle; pulls a pained
## face when hit; shows x x eyes when knocked out.
## Finishers can cut it in half top to bottom (split()), shatter it (shatter()), or char it
## black (burn()).

## Colours per character. skin/hair/eye also feed the top-bar portrait (PixelTex.portrait).
const LOOKS := {
	"demon_hunter": {"skin": Color("f2d0b4"), "hair": Color("e2e2ee"), "hair_dark": Color("a8a8bc"),
		"robe": Color("2a1e2a"), "robe_dark": Color("1a121a"), "trim": Color("8a1020"), "eye": Color("d01e2c"),
		"extra": "spiky"},
	"arcane_knight": {"skin": Color("f2d0b4"), "hair": Color("d6b048"), "hair_dark": Color("a8862e"),
		"robe": Color("b8c0cc"), "robe_dark": Color("7d8796"), "trim": Color("2e4fa0"), "eye": Color("2e6edc"),
		"extra": "helmet"},
	"verdant_ranger": {"skin": Color("f2d0b4"), "hair": Color("a0522d"), "hair_dark": Color("6e3418"),
		"robe": Color("2f6b3a"), "robe_dark": Color("6b4426"), "trim": Color("8fd36a"), "eye": Color("2f9a46"),
		"extra": "hood"},
	"flame_dragon": {"skin": Color("c8431e"), "hair": Color("e0b040"), "hair_dark": Color("8a2412"),
		"robe": Color("b8381a"), "robe_dark": Color("f0a040"), "trim": Color("e0b040"), "eye": Color("ffd23a"),
		"extra": "dragon"},
}
const GOLD := Color("d6b048")
const CARD_BACK := Color("27306b")
const CUT_Y := 0.74  # where the upper body sits on the lower one (and where a cut goes)
const SLUMP := 0.35  # forward lean when knocked out
const KO_TINT := Color(0.45, 0.45, 0.5)
const CHARRED := Color(0.03, 0.025, 0.025)  # burnt right through
const TURN_SHARE := 0.55  # how far an attacker turns towards its target
const WOUND_SHORT := 0.12  # Soul Reap wound length while the body shudders...
const WOUND_LONG := 0.46  # ...and once it tears open
## Draws one half of a cut body: everything on the wrong side of the cut plane is skipped.
## Where you would see into the hollow inside, the cut is capped instead: each inside pixel
## is drawn as the point where its view ray meets the cut plane, in a blocky charcoal pattern
## with ember-orange cells (they cool as `heat` falls), so the cut reads as a solid burnt face.
const HALF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest;
uniform bool use_tex = false;
uniform vec3 plane_point;
uniform vec3 plane_normal;
uniform float heat = 1.0;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float d = dot(world_pos - plane_point, plane_normal);
	if (d < 0.0) {
		discard;
	}
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(tex, UV);
	}
	if (FRONT_FACING) {
		ALBEDO = c.rgb;
	} else {
		// the cap: the cut-plane point behind this pixel, painted as burnt flesh
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 dir = normalize(world_pos - cam);
		float den = dot(dir, plane_normal);
		vec3 p = world_pos;
		if (abs(den) > 0.0001) {
			p = cam + dir * dot(plane_point - cam, plane_normal) / den;
		}
		vec3 t1 = normalize(cross(plane_normal, vec3(0.0, 1.0, 0.0)));
		vec3 t2 = cross(t1, plane_normal);
		vec2 cell = floor(vec2(dot(p - plane_point, t1), dot(p - plane_point, t2)) * 45.0);
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 char_c = mix(vec3(0.05, 0.035, 0.03), vec3(0.16, 0.07, 0.04), step(0.6, h));
		ALBEDO = char_c * 0.3;
		EMISSION = char_c * 0.7 + vec3(1.0, 0.3, 0.04) * step(0.88, h) * heat * 1.6;
	}
	ROUGHNESS = 1.0;
}
"""

static var _half_shader: Shader

var look_id := ""
var modulate := Color.WHITE:
	set(v):
		modulate = v
		for i in _mats.size():
			_mats[i].albedo_color = _base[i] * v
## Set once a finisher has broken the body (it no longer slumps, idles or blinks).
var destroyed := false

var _mats: Array[StandardMaterial3D] = []
var _base: Array[Color] = []
var _body: Node3D  # everything; bobs while idle (the root is moved by hit shakes)
var _upper: Node3D  # torso, arms, cards, head and weapon: comes off in a split
var _head: Node3D
var weapon: Node3D  # posed by attack_pose()
var _weapon_rest := Transform3D.IDENTITY
var _time := randf() * 10.0
var _faces: Dictionary = {}  # face mode -> texture
var _face_mat: StandardMaterial3D
var _blink_in := randf_range(1.0, 4.0)
var _face_hold := 0.0
var _knocked_out := false
var _fan: Array[MeshInstance3D] = []  # the cards held in the hands (dropped on death)
var _cards_dropped := false
var _arm_l: Node3D  # shoulder pivots: rotation.x < 0 raises the arm, > 0 lowers it
var _arm_r: Node3D
var _grip_l: Node3D  # where a held weapon sits in each hand
var _grip_r: Node3D
var _pose: Tween  # the attack / finisher motion playing now
var _rest_yaw := NAN  # the way it faces when not attacking (set on the first pose)
var _wounds: Array[MeshInstance3D] = []  # Soul Reap slash marks
var _halves: Array[Node3D] = []  # after a cut: the two halves...
var _half_mats: Array = []  # ...and each half's materials (their cut plane follows the half)


func _init(id: String, seated := true) -> void:
	look_id = id
	var look: Dictionary = LOOKS[id]
	_body = Node3D.new()
	add_child(_body)
	var skin: Color = look["skin"]
	# lower body: hips / legs block
	_box(_body, Vector3(0.44, 0.24, 0.3), Vector3(0, 0.62, 0), look["robe_dark"] if id != "flame_dragon" else look["robe"])
	_legs(look, seated)
	_upper = Node3D.new()
	_upper.position = Vector3(0, CUT_Y, 0)
	_body.add_child(_upper)
	# upper torso with a front stripe and collar in the trim colour
	_box(_upper, Vector3(0.44, 0.24, 0.3), Vector3(0, 0.1, 0), look["robe"])
	_box(_upper, Vector3(0.1, 0.22, 0.02), Vector3(0, 0.1, 0.156), look["trim"])
	_box(_upper, Vector3(0.3, 0.05, 0.31), Vector3(0, 0.215, 0), look["trim"])
	# arms on shoulder pivots; at rest they reach forward, hands together holding a fan of
	# cards. Each hand has a grip the weapon moves into while attacking.
	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.25, 0.06, -0.01)
		_upper.add_child(shoulder)
		_box(shoulder, Vector3(0.12, 0.12, 0.3), Vector3(0, 0, 0.15), look["robe"])
		_box(shoulder, Vector3(0.09, 0.09, 0.08), Vector3(-side * 0.13, 0, 0.32), skin)
		var grip := Node3D.new()
		grip.position = Vector3(-side * 0.13, 0, 0.33)
		shoulder.add_child(grip)
		if side < 0:
			_arm_l = shoulder
			_grip_l = grip
		else:
			_arm_r = shoulder
			_grip_r = grip
	for i in 4:
		var card := _box(_upper, Vector3(0.085, 0.12, 0.01), Vector3((i - 1.5) * 0.055, 0.14, 0.33), CARD_BACK)
		card.rotation.z = (1.5 - i) * 0.22
		_box(card, Vector3(0.05, 0.08, 0.012), Vector3.ZERO, GOLD.darkened(0.3))
		_fan.append(card)
	# head (big, chibi) with a pixel face on the front
	_head = Node3D.new()
	_head.position = Vector3(0, 0.43, 0)
	_upper.add_child(_head)
	_box(_head, Vector3(0.4, 0.38, 0.36), Vector3.ZERO, skin)
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.38)
	face.mesh = quad
	face.position = Vector3(0, 0, 0.185)
	for mode: String in ["open", "blink", "hurt", "ko"]:
		_faces[mode] = PixelTex.face(skin.lightened(0.15) if id == "flame_dragon" else skin, look["eye"], mode)
	_face_mat = _mat(Color.WHITE, _faces["open"])
	face.material_override = _face_mat
	_head.add_child(face)
	weapon = Node3D.new()
	_upper.add_child(weapon)
	match id:
		"demon_hunter":
			_build_demon_hunter(look)
		"arcane_knight":
			_build_arcane_knight(look)
		"verdant_ranger":
			_build_verdant_ranger(look)
		"flame_dragon":
			_build_flame_dragon(look)
	_weapon_rest = weapon.transform


## Legs under the hips: `seated` = thighs forward and shins down to the floor (at the table,
## on a chair), else standing straight (lobby and results previews).
func _legs(look: Dictionary, seated: bool) -> void:
	var dragon := look_id == "flame_dragon"
	var leg: Color = look["robe"] if dragon else look["robe_dark"]
	var boot: Color = look["robe"].darkened(0.35) if dragon else Color("3a2a1e")
	for side: float in [-1.0, 1.0]:
		var x := side * 0.11
		if seated:
			_box(_body, Vector3(0.17, 0.14, 0.4), Vector3(x, 0.565, 0.13), leg)  # thigh
			_box(_body, Vector3(0.15, 0.47, 0.16), Vector3(x, 0.28, 0.27), leg)  # shin
			_box(_body, Vector3(0.18, 0.1, 0.25), Vector3(x, 0.05, 0.31), boot)
		else:
			_box(_body, Vector3(0.16, 0.48, 0.18), Vector3(x, 0.27, 0.0), leg)
			_box(_body, Vector3(0.18, 0.1, 0.26), Vector3(x, 0.05, 0.04), boot)
		if dragon:  # claws on the toes
			for k in 2:
				_box(_body, Vector3(0.035, 0.035, 0.05), Vector3(x + (k - 0.5) * 0.08, 0.02,
					0.45 if seated else 0.18), look["trim"])


# Parts that overlap never share a face plane (that flickers in stripes): each is a little
# wider, deeper or further out than what it covers.

func _hair(look: Dictionary) -> void:
	_box(_head, Vector3(0.44, 0.48, 0.16), Vector3(0, -0.04, -0.14), look["hair_dark"])
	_box(_head, Vector3(0.46, 0.1, 0.42), Vector3(0, 0.22, 0), look["hair"])
	_box(_head, Vector3(0.44, 0.07, 0.06), Vector3(0, 0.15, 0.17), look["hair"])
	for side: float in [-1.0, 1.0]:
		_box(_head, Vector3(0.07, 0.4, 0.38), Vector3(side * 0.225, -0.02, 0.0), look["hair"])


## Demon Hunter: silver spiky hair, black coat with crimson trim, red scarf, a blood-red sword
## across the back.
func _build_demon_hunter(look: Dictionary) -> void:
	_hair(look)
	for i in 5:  # spikes
		var spike := _cone(_head, 0.06, 0.16, Vector3((i - 2) * 0.09, 0.32, -0.02 - absf(i - 2) * 0.02), look["hair"])
		spike.rotation.z = (2 - i) * 0.25
	_box(_upper, Vector3(0.48, 0.07, 0.34), Vector3(0, 0.2, 0), Color("a01428"))  # scarf
	_box(_upper, Vector3(0.12, 0.2, 0.04), Vector3(0.12, 0.08, -0.18), Color("a01428"))  # scarf tail
	weapon.position = Vector3(0.0, 0.2, -0.2)
	weapon.rotation.z = 0.8
	_box(weapon, Vector3(0.07, 0.62, 0.025), Vector3(0, 0.36, 0), Color("9a0f1e"))  # blade
	_box(weapon, Vector3(0.025, 0.6, 0.03), Vector3(0.03, 0.36, 0), Color("ff5a64"), true)  # glowing edge
	_box(weapon, Vector3(0.2, 0.04, 0.05), Vector3(0, 0.05, 0), Color("2a2a2a"))  # guard
	_box(weapon, Vector3(0.045, 0.16, 0.045), Vector3(0, -0.04, 0), Color("3a1018"))  # grip


## Arcane Knight: silver armour, blue tabard, open helmet with a blue plume, glowing sword at
## the side.
func _build_arcane_knight(look: Dictionary) -> void:
	_box(_head, Vector3(0.44, 0.07, 0.06), Vector3(0, 0.13, 0.17), look["hair"])  # fringe under the helmet
	var steel: Color = look["robe"]
	_box(_head, Vector3(0.48, 0.1, 0.44), Vector3(0, 0.24, 0), steel)  # helmet top
	_box(_head, Vector3(0.48, 0.46, 0.14), Vector3(0, 0.0, -0.16), steel)  # back
	for side: float in [-1.0, 1.0]:
		_box(_head, Vector3(0.05, 0.42, 0.42), Vector3(side * 0.235, 0.02, 0.0), steel)  # cheek guards
	_box(_head, Vector3(0.5, 0.04, 0.46), Vector3(0, 0.19, 0.0), GOLD)  # band
	_box(_head, Vector3(0.06, 0.2, 0.3), Vector3(0, 0.38, -0.04), look["trim"])  # plume
	for side: float in [-1.0, 1.0]:  # pauldrons
		_box(_upper, Vector3(0.16, 0.1, 0.32), Vector3(side * 0.26, 0.19, 0), steel.lightened(0.1))
	weapon.position = Vector3(0.33, 0.0, 0.06)
	_box(weapon, Vector3(0.05, 0.6, 0.02), Vector3(0, 0.36, 0), Color("6fe0ff"), true)  # light blade
	_box(weapon, Vector3(0.18, 0.04, 0.05), Vector3(0, 0.05, 0), GOLD)
	_box(weapon, Vector3(0.045, 0.14, 0.045), Vector3(0, -0.03, 0), look["trim"])


## Verdant Ranger: green hood and cloak, auburn hair, leather, a wooden bow with a glowing
## string and a quiver on the back.
func _build_verdant_ranger(look: Dictionary) -> void:
	_hair(look)
	var green: Color = look["robe"]
	_box(_head, Vector3(0.56, 0.12, 0.48), Vector3(0, 0.27, -0.01), green)
	_box(_head, Vector3(0.56, 0.52, 0.2), Vector3(0, 0.0, -0.19), green)
	for side: float in [-1.0, 1.0]:
		_box(_head, Vector3(0.06, 0.44, 0.44), Vector3(side * 0.27, 0.02, -0.01), green)
	_box(_upper, Vector3(0.48, 0.3, 0.06), Vector3(0, 0.08, -0.18), green.darkened(0.2))  # cloak
	_box(_upper, Vector3(0.46, 0.05, 0.32), Vector3(0, 0.0, 0), look["robe_dark"])  # belt
	# quiver with arrows
	_box(_upper, Vector3(0.1, 0.32, 0.1), Vector3(-0.14, 0.22, -0.24), look["robe_dark"])
	for k in 3:
		_box(_upper, Vector3(0.02, 0.12, 0.02), Vector3(-0.17 + k * 0.03, 0.42, -0.24), look["trim"])
	weapon.position = Vector3(0.33, 0.12, 0.08)
	var wood := Color("7a4a26")
	for k in 7:  # the bow's curve
		var a := (k - 3) * 0.22
		var seg := _box(weapon, Vector3(0.035, 0.1, 0.035), Vector3(0, sin(a) * 0.3, -cos(a) * 0.08 + 0.08), wood)
		seg.rotation.x = -a * 0.6
	_box(weapon, Vector3(0.008, 0.6, 0.008), Vector3(0, 0, 0.09), look["trim"], true)  # string


## Flame Dragon: red-scaled dragon folk: snout, golden horns, small wings, a pale belly and
## fiery claws.
func _build_flame_dragon(look: Dictionary) -> void:
	var scale_c: Color = look["skin"]
	_box(_head, Vector3(0.44, 0.1, 0.4), Vector3(0, 0.2, 0), look["hair_dark"])  # brow ridge / crest
	_box(_head, Vector3(0.24, 0.14, 0.14), Vector3(0, -0.11, 0.24), scale_c.lightened(0.08))  # snout
	_box(_head, Vector3(0.03, 0.03, 0.02), Vector3(-0.05, -0.06, 0.315), Color("2a0a06"))  # nostrils
	_box(_head, Vector3(0.03, 0.03, 0.02), Vector3(0.05, -0.06, 0.315), Color("2a0a06"))
	for side: float in [-1.0, 1.0]:
		var horn := _cone(_head, 0.05, 0.24, Vector3(side * 0.15, 0.3, -0.1), look["hair"])
		horn.rotation.x = -0.6
		horn.rotation.z = -side * 0.3
		var wing := _box(_upper, Vector3(0.3, 0.24, 0.02), Vector3(side * 0.26, 0.24, -0.2), look["hair_dark"])
		wing.rotation.z = side * 0.5
		wing.rotation.y = side * 0.4
	_box(_upper, Vector3(0.2, 0.2, 0.02), Vector3(0, 0.08, 0.158), look["robe_dark"])  # belly
	for grip: Node3D in [_grip_l, _grip_r]:  # fiery claws on both hands (no weapon to hold)
		for k in 3:
			var claw := _cone(grip, 0.015, 0.07, Vector3((k - 1) * 0.025, 0.0, 0.04), Color("ffb347"))
			claw.rotation.x = PI / 2


# ---------- animation ----------

## The attack, timed so the blow lands (or the shot leaves) at `impact` seconds: the cards are
## put away, the weapon comes into the hand, the arms wind up for 60% of the time and strike
## in the rest, hold the follow-through, then everything goes back.
##   swords (demon hunter, arcane knight): right arm raised behind the head, slashed down
##   across; the demon hunter also lunges `lunge` (world offset) at the target.
##   bow (verdant ranger): bow arm up to aim, string hand drawn back, loosed.
##   claws (flame dragon): both arms raised, raked down one after the other.
func attack_pose(impact: float, lunge := Vector3.ZERO, target := Vector3.INF) -> void:
	var w := impact * 0.6
	var s := impact - w
	var t := _begin_pose()
	var home := position
	_turn_to(t, target, w * 0.5)
	match look_id:
		"demon_hunter", "arcane_knight":
			_hold_weapon(_grip_r, Transform3D.IDENTITY)
			t.tween_property(_arm_r, "rotation", Vector3(-2.5, 0, -0.3), w).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(_arm_l, "rotation", Vector3(-0.5, 0, 0.3), w)
			t.parallel().tween_property(_upper, "rotation:y", -0.25, w)
			if lunge != Vector3.ZERO:
				t.parallel().tween_property(self, "position", home + lunge, impact).set_ease(Tween.EASE_OUT)
			t.tween_property(_arm_r, "rotation", Vector3(0.5, 0, 0.5), s).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(_upper, "rotation:y", 0.3, s)
		"verdant_ranger":
			_hold_weapon(_grip_l, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
			t.tween_property(_arm_l, "rotation", Vector3(-1.35, 0.2, 0), w * 0.45)
			t.parallel().tween_property(_arm_r, "rotation", Vector3(-1.35, 0, 0), w * 0.45)
			t.tween_property(_arm_r, "rotation", Vector3(-1.35, 0.9, 0), w * 0.55)  # draw
			t.tween_property(_arm_r, "rotation", Vector3(-1.15, -0.25, 0), s * 0.4)  # loose
			t.tween_interval(s * 0.6)
		"flame_dragon":
			t.tween_property(_arm_r, "rotation", Vector3(-2.3, 0, -0.4), w)
			t.parallel().tween_property(_arm_l, "rotation", Vector3(-2.3, 0, 0.4), w)
			t.parallel().tween_property(_upper, "rotation:x", -0.15, w)
			t.tween_property(_arm_r, "rotation", Vector3(0.6, 0, 0.3), s).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(_upper, "rotation:x", 0.3, s)
			t.parallel().tween_property(_arm_l, "rotation", Vector3(0.6, 0, -0.3), s).set_delay(s * 0.4)
	t.tween_interval(impact * 0.3)  # follow-through
	_end_pose(t, impact * 0.5, home if lunge != Vector3.ZERO else position)


## The finisher's own moves, from the knockout hit (times x `k`, matching AttackFx):
##   demon hunter: four slashes in a flurry; arcane knight: the sword raised high overhead and
##   brought straight down; verdant ranger: the bow aimed at the sky, drawn and loosed;
##   flame dragon: arms flung back, leaning in for the long breath of fire.
func finisher_pose(k: float, target := Vector3.INF) -> void:
	var t := _begin_pose()
	_turn_to(t, target, 0.08 * k)
	match look_id:
		"demon_hunter":
			_hold_weapon(_grip_r, Transform3D.IDENTITY)
			for i in 4:
				t.tween_property(_arm_r, "rotation", Vector3(-2.2, 0, -0.5 if i % 2 == 0 else 0.5), 0.06 * k)
				t.tween_property(_arm_r, "rotation", Vector3(0.5, 0, 0.5 if i % 2 == 0 else -0.5), 0.07 * k)
			t.tween_interval(1.0 * k)
		"arcane_knight":
			_hold_weapon(_grip_r, Transform3D.IDENTITY)
			t.tween_property(_arm_r, "rotation", Vector3(-3.0, 0, 0), 0.14 * k).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(_arm_l, "rotation", Vector3(-3.0, 0, 0), 0.14 * k)  # two-handed
			t.tween_property(_arm_r, "rotation", Vector3(0.45, 0, 0), 0.08 * k).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(_arm_l, "rotation", Vector3(0.45, 0, 0), 0.08 * k)
			t.parallel().tween_property(_upper, "rotation:x", 0.25, 0.08 * k)
			t.tween_interval(1.0 * k)
		"verdant_ranger":
			_hold_weapon(_grip_l, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
			t.tween_property(_arm_l, "rotation", Vector3(-2.6, 0.1, 0), 0.12 * k)
			t.parallel().tween_property(_arm_r, "rotation", Vector3(-2.6, 0, 0), 0.12 * k)
			t.parallel().tween_property(_upper, "rotation:x", -0.2, 0.12 * k)
			t.tween_property(_arm_r, "rotation", Vector3(-2.3, 0.8, 0), 0.15 * k)  # draw
			t.tween_property(_arm_r, "rotation", Vector3(-2.7, -0.2, 0), 0.04 * k)  # loose
			t.tween_interval(0.6 * k)
		"flame_dragon":
			# rears back growling and drawing breath, then lunges in for the fire
			t.tween_property(_arm_r, "rotation", Vector3(-0.4, 0, -0.9), 0.15 * k)
			t.parallel().tween_property(_arm_l, "rotation", Vector3(-0.4, 0, 0.9), 0.15 * k)
			t.parallel().tween_property(_upper, "rotation:x", -0.3, 0.15 * k)
			t.tween_interval(0.35 * k)
			t.tween_property(_upper, "rotation:x", 0.3, 0.1 * k).set_ease(Tween.EASE_OUT)
			t.tween_interval(1.5 * k)
	_end_pose(t, 0.4 * k, position)


## Turn towards `target` (a world point) at the start of a pose, alongside its first move;
## _end_pose() turns back.
func _turn_to(t: Tween, target: Vector3, seconds: float) -> void:
	if not target.is_finite():
		return
	var d := target - global_position
	var yaw := atan2(d.x, d.z)
	# the short way round, and only part of the way: side-on to you, so the arms show
	yaw = _rest_yaw + wrapf(yaw - _rest_yaw, -PI, PI) * TURN_SHARE
	t.parallel().tween_property(self, "rotation:y", yaw, seconds)


func _begin_pose() -> Tween:
	if _pose:
		_pose.kill()
	if is_nan(_rest_yaw):
		_rest_yaw = rotation.y
	for c in _fan:
		c.visible = false  # hands busy
	_pose = create_tween()
	return _pose


## Arms, body and position back to rest; the weapon goes back to its place and the cards
## back into the hands.
func _end_pose(t: Tween, back: float, home: Vector3) -> void:
	t.tween_property(_arm_r, "rotation", Vector3.ZERO, back)
	t.parallel().tween_property(_arm_l, "rotation", Vector3.ZERO, back)
	t.parallel().tween_property(_upper, "rotation", Vector3.ZERO, back)
	t.parallel().tween_property(self, "position", home, back)
	t.parallel().tween_property(self, "rotation:y", _rest_yaw, back)
	t.tween_callback(func() -> void:
		_put_weapon_back()
		for c in _fan:
			c.visible = not _cards_dropped and not destroyed)


func _hold_weapon(grip: Node3D, xform: Transform3D) -> void:
	if weapon.get_parent() != grip:
		weapon.reparent(grip, false)
	weapon.transform = xform


func _put_weapon_back() -> void:
	if weapon.get_parent() != _upper:
		weapon.reparent(_upper, false)
	weapon.transform = _weapon_rest


## Drop the shared cut shader (King's Verdict) when the table closes: a static resource would
## otherwise outlive the renderer at exit and be reported as leaked.
static func clear() -> void:
	_half_shader = null


## Menu table play: the right arm swings up and flicks forward, as if throwing dice or a
## card, `seconds` in all.
func throw_gesture(seconds := 0.6) -> void:
	var t := _begin_pose()
	t.tween_property(_arm_r, "rotation", Vector3(-1.9, 0, -0.2), seconds * 0.4).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_upper, "rotation:y", -0.2, seconds * 0.4)
	t.tween_property(_arm_r, "rotation", Vector3(-0.6, 0, 0.1), seconds * 0.25).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_upper, "rotation:y", 0.15, seconds * 0.25)
	_end_pose(t, seconds * 0.35, position)


## Menu table play: both arms up for a good roll, a little hop.
func cheer(seconds := 0.9) -> void:
	var t := _begin_pose()
	t.tween_property(_arm_r, "rotation", Vector3(-2.6, 0, -0.35), seconds * 0.25).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_arm_l, "rotation", Vector3(-2.6, 0, 0.35), seconds * 0.25).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_upper, "rotation:x", -0.12, seconds * 0.25)
	t.tween_property(_arm_r, "rotation", Vector3(-2.2, 0, -0.5), seconds * 0.2)
	t.parallel().tween_property(_arm_l, "rotation", Vector3(-2.2, 0, 0.5), seconds * 0.2)
	t.tween_property(_arm_r, "rotation", Vector3(-2.6, 0, -0.35), seconds * 0.2)
	t.parallel().tween_property(_arm_l, "rotation", Vector3(-2.6, 0, 0.35), seconds * 0.2)
	_end_pose(t, seconds * 0.35, position)


## Hit: a pained face for a moment and the head jerks back.
func hurt() -> void:
	if _knocked_out:
		return
	_face_mat.albedo_texture = _faces["hurt"]
	_face_hold = 0.9
	var t := _head.create_tween()
	t.tween_property(_head, "rotation:x", -0.35, 0.07)
	t.tween_property(_head, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_knocked_out(on: bool) -> void:
	_knocked_out = on
	_face_hold = 0.0
	_face_mat.albedo_texture = _faces["ko" if on else "open"]


## King's Verdict: cut in half top to bottom. The body is replaced by two copies, each drawn
## only on its side of the cut (HALF_SHADER: the cut capped with a burnt face). For a second
## the halves slowly part; then they topple over sideways. Times x `k`.
func split(k: float) -> void:
	destroyed = true
	set_knocked_out(true)
	if _half_shader == null:
		_half_shader = Shader.new()
		_half_shader.code = HALF_SHADER
	for side: float in [-1.0, 1.0]:
		var half := _body.duplicate() as Node3D
		add_child(half)
		var mats: Array[ShaderMaterial] = []
		for mi: MeshInstance3D in half.find_children("*", "MeshInstance3D", true, false):
			var std := mi.material_override as StandardMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = _half_shader
			sm.set_shader_parameter("albedo", std.albedo_color)
			if std.albedo_texture:
				sm.set_shader_parameter("tex", std.albedo_texture)
				sm.set_shader_parameter("use_tex", true)
			mi.material_override = sm
			mats.append(sm)
		_halves.append(half)
		_half_mats.append(mats)
		# a half falling towards the table only tips onto its edge; the other drops flat
		var outward := global_basis.x.normalized() * side
		var toward_table := (-global_position * Vector3(1, 0, 1)).normalized()
		var lie := 0.7 if outward.dot(toward_table) > 0.3 else 1.45
		var home := half.position
		var t := half.create_tween()
		t.tween_property(half, "position", home + Vector3(side * 0.1, 0, 0), 1.0 * k) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(half, "rotation:z", -side * 0.08, 1.0 * k)
		t.tween_property(half, "rotation:z", -side * lie, 0.75 * k) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)  # falls faster and faster
		t.parallel().tween_property(half, "position", home + Vector3(side * 0.3, -0.05, 0) * (lie / 1.45), 0.75 * k)
		t.tween_property(half, "rotation:z", -side * (lie - 0.13), 0.08 * k)  # a little bounce on landing
		t.tween_property(half, "rotation:z", -side * lie, 0.1 * k)
		# the embers on the cut cool down
		var cool := func(v: float) -> void:
			for sm: ShaderMaterial in mats:
				sm.set_shader_parameter("heat", v)
		half.create_tween().tween_method(cool, 1.0, 0.25, 3.0 * k)
	_body.visible = false
	_update_cut()


## Keep each half's cut plane on the half as it moves: the plane through its centre line,
## facing the side that half keeps.
func _update_cut() -> void:
	for i in _halves.size():
		var half := _halves[i]
		var side := -1.0 if i == 0 else 1.0
		var normal := half.global_basis.x.normalized() * side
		for sm: ShaderMaterial in _half_mats[i]:
			sm.set_shader_parameter("plane_point", half.global_position)
			sm.set_shader_parameter("plane_normal", normal)


## The held cards leave the hands (the tavern drops them on the table).
func drop_cards() -> void:
	_cards_dropped = true
	for c in _fan:
		c.visible = false


## Soul Reap: the `i`-th slash leaves a short glowing red wound across the chest or face.
func slash_mark(i: int) -> void:
	var on_head := i % 2 == 1
	var mark := _box(_head if on_head else _upper, Vector3(WOUND_LONG, 0.025, 0.01),
		Vector3(0, -0.02, 0.192) if on_head else Vector3(0, 0.1, 0.162), Color("ff2a3a"), true)
	mark.rotation.z = [0.6, -0.6, 0.15, -0.9][i % 4]
	mark.scale.x = WOUND_SHORT / WOUND_LONG
	_wounds.append(mark)


## Soul Reap, just before the burst: every wound tears open to full length at once.
func open_wounds() -> void:
	for w in _wounds:
		w.scale = Vector3(1.0, 1.6, 1.0)


## A shudder of `duration` seconds (between the last slash and the burst).
func tremble(duration: float) -> void:
	var t := _body.create_tween()
	var steps := int(duration / 0.05)
	for n in steps:
		t.tween_property(_body, "position:x", randf_range(-0.015, 0.015), 0.05)
	t.tween_property(_body, "position:x", 0.0, 0.05)


## Where the head is, now or (`slumped`) in the knocked-out pose.
func head_point(slumped := false) -> Vector3:
	var keep := rotation
	if slumped:
		rotation.x = SLUMP
	var p := _head.global_position
	rotation = keep
	return p


## Final Arrow: skewered. Snaps straight into the slumped knocked-out pose, then the colour
## fades to the knocked-out grey over `fade` seconds.
func pinned(fade: float) -> void:
	destroyed = true
	set_knocked_out(true)
	rotation.x = SLUMP
	create_tween().tween_property(self, "modulate", KO_TINT, fade)


## Soul Reap: the body is gone; returns its colours (for the flying pieces) and hides it.
func shatter() -> Array[Color]:
	destroyed = true
	visible = false
	var look: Dictionary = LOOKS[look_id]
	return [look["skin"], look["hair"], look["robe"], look["robe_dark"], look["trim"]]


## Dragon's Judgment: blackens to charcoal over `duration` while it burns, still and slumped.
func burn(duration: float) -> void:
	destroyed = true
	set_knocked_out(true)
	var t := create_tween()
	t.tween_property(self, "modulate", CHARRED, duration)
	t.parallel().tween_property(self, "rotation:x", 0.3, duration)


func _process(delta: float) -> void:
	_time += delta
	if not _halves.is_empty():
		_update_cut()
	if _knocked_out or destroyed:
		return  # slumped and still
	# idle: slow breathing and a little look around
	_body.position.y = sin(_time * 2.0) * 0.012
	_head.rotation.y = sin(_time * 0.6) * 0.18
	_head.rotation.z = sin(_time * 0.9) * 0.04
	# blinking every few seconds (now and then twice in a row); hurt faces hold a little longer
	if _face_hold > 0.0:
		_face_hold -= delta
		if _face_hold <= 0.0:
			_face_mat.albedo_texture = _faces["open"]
		return
	_blink_in -= delta
	if _blink_in <= 0.0:
		_face_mat.albedo_texture = _faces["blink"]
		_face_hold = 0.12
		_blink_in = 0.25 if randf() < 0.2 else randf_range(2.0, 5.0)


# ---------- building helpers ----------

func _mat(color: Color, tex: Texture2D = null, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # glowing parts ignore the room light
	_mats.append(m)
	_base.append(color)
	return m


func _add(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, null, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, box_size: Vector3, pos: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	return _add(parent, mesh, pos, color, glow)


func _cone(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return _add(parent, mesh, pos, color)
