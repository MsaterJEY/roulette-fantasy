class_name CharacterSelect
extends Control
## Before the game: pick your character. Four cards, each with the hero turning slowly in
## 3D, its name, weapon (your Attack card), attack move and finisher. Click one, then
## "เริ่มเกม"; the bots get the other characters.

signal chosen(id: String)

const CARD_SIZE := Vector2(212, 372)

var _picked := ""
var _cards: Dictionary = {}  # id -> PanelContainer
var _models: Array[Character3D] = []
var _start: Button
var sfx: Sfx  # set by the table before this enters the tree


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "เลือกตัวละคร"
	title.position = Vector2(0, 14)
	title.size = Vector2(960, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiStyle.ACTIVE)
	title.add_theme_color_override("font_outline_color", Color("2a1408"))
	title.add_theme_constant_override("outline_size", 8)
	add_child(title)
	var sub := Label.new()
	sub.text = "การ์ดโจมตีของคุณจะเป็นอาวุธของตัวละคร · บอทจะได้ตัวที่เหลือ"
	sub.position = Vector2(0, 54)
	sub.size = Vector2(960, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	add_child(sub)
	var full := ScreenMode.button()
	full.position = Vector2(960 - 16 - 44, 17)
	add_child(full)

	var chars := CharacterDB.all()
	var gap := 14.0
	var left := (960.0 - chars.size() * CARD_SIZE.x - (chars.size() - 1) * gap) / 2
	for i in chars.size():
		var card := _make_card(chars[i])
		card.position = Vector2(left + i * (CARD_SIZE.x + gap), 84)
		add_child(card)

	_start = Button.new()
	_start.text = "เริ่มเกม"
	_start.position = Vector2(400, 474)
	_start.custom_minimum_size = Vector2(160, 48)
	_start.add_theme_font_size_override("font_size", 20)
	_start.add_theme_stylebox_override("normal", UiStyle.panel(UiStyle.BRASS.darkened(0.3), UiStyle.BRASS, 2, 8))
	_start.add_theme_stylebox_override("hover", UiStyle.panel(UiStyle.BRASS.darkened(0.1), UiStyle.ACTIVE, 2, 8))
	_start.add_theme_stylebox_override("disabled", UiStyle.panel(UiStyle.WOOD_DARK, UiStyle.TEXT_DIM, 1, 8))
	_start.disabled = true
	_start.pressed.connect(func() -> void:
		if sfx:
			sfx.play("confirm")
		chosen.emit(_picked))
	add_child(_start)


func _make_card(c: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pick(c["id"]))
	_cards[c["id"]] = card
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	box.add_child(_preview(c["id"]))
	var name := _label(box, c["name"], 20, UiStyle.ACTIVE)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var en := _label(box, c["name_en"], 12, UiStyle.TEXT_DIM)
	en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var weapon := HBoxContainer.new()
	weapon.alignment = BoxContainer.ALIGNMENT_CENTER
	weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(weapon)
	weapon.add_child(Icons.rect(c["icon"], 22))
	_label(weapon, "อาวุธ: " + c["weapon"], 13, UiStyle.TEXT)
	_label(box, "ท่าโจมตี: " + c["attack"], 12, UiStyle.TEXT)
	_label(box, "ท่าสังหาร: " + c["finisher"], 12, Color("ff8a6a"))
	var desc := _label(box, c["finisher_desc"], 11, UiStyle.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - 20, 0)
	_style(card, false)
	return card


## A little 3D stage with the character turning slowly.
func _preview(id: String) -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(CARD_SIZE.x - 16, 170)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(vp)
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
	var model := Character3D.new(id, false)  # standing
	vp.add_child(model)
	_models.append(model)
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	var eye := Vector3(0, 0.95, 2.75)  # not in the tree yet, so no look_at(); head to feet
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.78, 0) - eye), eye)
	return holder


func pick(id: String) -> void:
	if sfx and id != _picked:
		sfx.play("select")
	_picked = id
	for k: String in _cards:
		_style(_cards[k], k == id)
	_start.disabled = false


func _style(card: PanelContainer, on: bool) -> void:
	var s := UiStyle.panel(Color(UiStyle.WOOD_DARK, 0.96), UiStyle.ACTIVE if on else UiStyle.BRASS.darkened(0.3), 3 if on else 2, 10)
	if on:
		s.shadow_color = Color(UiStyle.ACTIVE, 0.4)
		s.shadow_size = 10
	card.add_theme_stylebox_override("panel", s)
	card.modulate = Color.WHITE if on or _picked == "" else Color(0.75, 0.75, 0.75)


func _label(parent: Container, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	for m in _models:
		m.rotation.y += delta * 0.6
