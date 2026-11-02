class_name CoinView
extends Control
## A gold coin icon drawn in code.


func _init() -> void:
	custom_minimum_size = Vector2(22, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2
	var r := minf(size.x, size.y) / 2
	draw_circle(c, r, UiStyle.RING.darkened(0.35))
	draw_circle(c, r - 2, UiStyle.RING)
	draw_arc(c, r * 0.55, 0, TAU, 24, UiStyle.RING.darkened(0.3), 1.5, true)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.18, Color(1, 1, 1, 0.55))
