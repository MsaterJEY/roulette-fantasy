class_name DiceView
extends Control
## One die face (1–6) drawn in code: ivory square with dark pips.

const PIPS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5),
		Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
}

var value := 1:
	set(v):
		value = clampi(v, 1, 6)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UiStyle.CARD
	box.border_color = UiStyle.WOOD
	box.set_border_width_all(2)
	box.set_corner_radius_all(7)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var r := size.x * 0.09
	for p: Vector2 in PIPS[value]:
		draw_circle(p * size, r, Color("7a1f1f") if value == 1 else UiStyle.CARD_TEXT)
