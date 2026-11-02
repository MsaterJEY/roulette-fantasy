class_name UiStyle
extends RefCounted
## Shared colors, the Thai-capable theme and panel styles (vintage casino look).

const ROOM := Color("1a1410")
const FELT := Color("1f4d33")
const WOOD := Color("4a2f1c")
const WOOD_DARK := Color("2e1c10")
const BRASS := Color("c9a227")
const TEXT := Color("f3e9d2")
const TEXT_DIM := Color("b9a98a")
const CARD := Color("efe3c4")
const CARD_TEXT := Color("2a1d12")
const HP := Color("d64545")
const SHIELD := Color("4f8fd6")
const RING := Color("f0c419")
const EMPTY := Color(1, 1, 1, 0.12)
const ACTIVE := Color("ffd76a")

const TYPE_COLORS := {
	"attack": Color("c0392b"),
	"defense": Color("2e86c1"),
	"help": Color("27ae60"),
	"curse": Color("8e44ad"),
}


static func make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	# Windows fonts with Thai glyphs first; Godot's built-in font has no Thai.
	font.font_names = PackedStringArray(["Leelawadee UI", "Tahoma", "Segoe UI"])
	t.default_font = font
	if OS.has_feature("web"):  # a browser has no system fonts: bundled Noto fonts (OFL)
		var web: FontFile = load("res://assets/fonts/NotoSansThai.ttf")
		web.fallbacks = [load("res://assets/fonts/NotoSansSymbols2-Regular.ttf"),  # ★ ◆ ▲ ♥ ✕
			load("res://assets/fonts/NotoSansMath-Regular.ttf")]  # →
		t.default_font = web
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


static func panel(bg: Color, border: Color, width: int = 2, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(8)
	return s
