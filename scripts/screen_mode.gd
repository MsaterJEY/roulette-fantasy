class_name ScreenMode
extends RefCounted
## Full screen on and off, from the square button in the top-right corner of every screen
## (menu, character select, table, results). On the web it fills the monitor the same way;
## Esc (the browser's own key) leaves it, and the button's icon follows.


static func is_full() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func toggle() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_full() else DisplayServer.WINDOW_MODE_FULLSCREEN)


## A `side` x `side` brass button that toggles full screen; place it and add it yourself.
static func button(side := 44.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel icons stay crisp
	b.add_theme_constant_override("icon_max_width", 22)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiStyle.panel(UiStyle.BRASS.darkened(0.3), UiStyle.BRASS, 2, 6))
	b.add_theme_stylebox_override("hover", UiStyle.panel(UiStyle.BRASS.darkened(0.1), UiStyle.ACTIVE, 2, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.panel(UiStyle.BRASS.darkened(0.45), UiStyle.BRASS, 2, 6))
	b.pressed.connect(toggle)
	_show(b)
	# the window changes size when it goes full screen or back (also by Esc in a browser)
	var refresh := func() -> void: _show(b)
	b.tree_entered.connect(func() -> void: b.get_tree().root.size_changed.connect(refresh))
	b.tree_exiting.connect(func() -> void: b.get_tree().root.size_changed.disconnect(refresh))
	return b


static func _show(b: Button) -> void:
	var full := is_full()
	b.icon = Icons.get_icon("windowed" if full else "fullscreen")
	b.tooltip_text = "ออกจากเต็มจอ" if full else "ขยายเต็มจอ"
