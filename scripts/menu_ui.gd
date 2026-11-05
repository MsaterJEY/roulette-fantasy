class_name MenuUi
extends RefCounted
## Building blocks for the menu screens, in the style of the user's interface mockups: dark
## wood panels with gold frames, big gold buttons with an icon, a Thai label and a small
## English line, the gold game logo.

const GOLD := Color("e8b84a")
const GOLD_DARK := Color("8a6420")
const PANEL := Color(0.09, 0.06, 0.04, 0.93)
const DIM := Color(0.06, 0.04, 0.03, 0.55)


static func panel_style(border := GOLD_DARK, width := 2, bg := PANEL) -> StyleBoxFlat:
	var s := UiStyle.panel(bg, border, width, 10)
	s.set_content_margin_all(14)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	return s


static func panel(at: Vector2, size: Vector2, border := GOLD_DARK) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = at
	p.custom_minimum_size = size
	p.size = size
	p.add_theme_stylebox_override("panel", panel_style(border))
	return p


## A big menu button: icon, Thai label, small English line underneath. `primary` = the gold one.
static func big_button(icon: String, thai: String, english: String, primary := false, width := 230.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 64)
	var normal := UiStyle.panel(Color("8a6420") if primary else Color("2b1d12"), GOLD if primary else GOLD_DARK, 2, 10)
	var hover := UiStyle.panel(Color("a67a2a") if primary else Color("3a2818"), Color("ffe08a"), 3, 10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", UiStyle.panel(Color("6a4a18"), GOLD, 2, 10))
	b.add_theme_stylebox_override("disabled", UiStyle.panel(Color("1e150e"), Color("4a3a28"), 1, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	b.add_child(row)
	if icon != "":
		var ic := Icons.rect(icon, 30)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -4)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	texts.add_child(label(thai, 20, Color("fff2cc") if primary else UiStyle.TEXT))
	if english != "":
		texts.add_child(label(english, 10, GOLD if primary else UiStyle.TEXT_DIM))
	return b


## A small button (back, toggles, footer links).
## On a phone the keyboard types into a hidden box on the web page, which knows nothing of the
## field's max_length: letters past it would pile up unseen and Backspace would seem dead.
## This hands the limit to the page (index.html's focusin script) while the field has focus.
static func keyboard_limit(edit: LineEdit) -> void:
	if OS.has_feature("web"):
		edit.focus_entered.connect(func() -> void:
			JavaScriptBridge.eval("window.rfMaxLen=%d" % edit.max_length, true))


static func small_button(text: String, icon := "", width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	if icon != "":
		b.icon = Icons.get_icon(icon)
		b.add_theme_constant_override("icon_max_width", 18)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, 34)
	b.add_theme_stylebox_override("normal", UiStyle.panel(Color("2b1d12"), GOLD_DARK, 1, 8))
	b.add_theme_stylebox_override("hover", UiStyle.panel(Color("3a2818"), GOLD, 1, 8))
	b.add_theme_stylebox_override("pressed", UiStyle.panel(Color("6a4a18"), GOLD, 2, 8))
	b.add_theme_stylebox_override("disabled", UiStyle.panel(Color("1e150e"), Color("4a3a28"), 1, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## A toggle among options (players 2/3/4 ...): gold when chosen.
static func choice_button(text: String, group: ButtonGroup, on: bool) -> Button:
	var b := small_button(text)
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = on
	b.custom_minimum_size = Vector2(96, 36)
	b.add_theme_stylebox_override("pressed", UiStyle.panel(Color("8a6420"), GOLD, 2, 8))
	b.add_theme_stylebox_override("hover_pressed", UiStyle.panel(Color("a67a2a"), Color("ffe08a"), 2, 8))
	return b


static func label(text: String, size := 14, color := UiStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The game logo: ROULETTE / FANTASY in gold with a dark outline.
static func logo(size := 46) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -size / 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for word: String in ["ROULETTE", "FANTASY"]:
		var l := label(word, size, GOLD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color("2a1408"))
		l.add_theme_constant_override("outline_size", size / 4)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_y", 3)
		box.add_child(l)
	return box


## A screen title: "◆ text ◆" on a dark plate.
static func title(text: String, size := 22) -> PanelContainer:
	var p := PanelContainer.new()
	var s := UiStyle.panel(Color(0.07, 0.05, 0.04, 0.9), GOLD_DARK, 1, 14)
	s.content_margin_left = 22
	s.content_margin_right = 22
	p.add_theme_stylebox_override("panel", s)
	var l := label("◆  " + text + "  ◆", size, GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
