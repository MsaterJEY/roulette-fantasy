class_name SeatPanel
extends PanelContainer
## One player's card in the top bar: portrait, name, effect icons (top-right), HP pips with
## the hand size, ring pips with the shard count. Click it to pick that player as a card
## target while targeting. Your own card is blue with a star by the name, so it's easy to
## tell from the bots'.

signal clicked(seat: int)

const TARGET := Color("ff7b54")
const MAX_CHIPS := 3  # effect icons that fit in a card's corner
const MINE_BG := Color(0.07, 0.17, 0.27, 0.95)
const MINE_BORDER := Color("5ec8ff")

var player: PlayerData
static var rings_max := PlayerData.RINGS_TO_WIN  # ring pips to show (the room's rings to win)
static var hp_max := PlayerData.MAX_HP  # HP pips to show (drops every few rounds)
static var compact := false  # 5-6 players: no portrait, so the cards fit the bar
var _name_label: Label
var _hp_pips: HBoxContainer
var _ring_pips: HBoxContainer
var _cards_label: Label
var _shards_label: Label
var _status_bar: HBoxContainer
var _active := false
var _targetable := false
var _pulse: Tween


func setup(p: PlayerData) -> void:
	player = p
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var portrait := TextureRect.new()
	portrait.texture = PixelTex.portrait(p.character if p.character != "" else "demon_hunter")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(32, 32)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = not compact
	row.add_child(portrait)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	if p.seat == 0 and not p.is_bot:
		top.add_child(Icons.rect("star", 14))  # marks your own card
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.custom_minimum_size = Vector2(30, 0)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	top.add_child(_name_label)
	_status_bar = HBoxContainer.new()
	_status_bar.add_theme_constant_override("separation", 1)
	_status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_status_bar)

	_hp_pips = _stat_row(box, "HP", UiStyle.HP)
	_cards_label = _count(_hp_pips.get_parent(), "cards")
	_ring_pips = _stat_row(box, "แหวน", UiStyle.RING)
	_shards_label = _count(_ring_pips.get_parent(), "shard")
	_ring_pips.get_parent().visible = rings_max > 0  # rings off: no ring row
	refresh()


func set_active(on: bool) -> void:
	if on == _active:
		refresh()
		return
	_active = on
	if _pulse:
		_pulse.kill()
		_pulse = null
	self_modulate = Color.WHITE
	if on:
		# slow glow pulse while it is this player's turn
		_pulse = create_tween().set_loops()
		_pulse.tween_property(self, "self_modulate", Color(1.12, 1.09, 1.02), 0.7).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(self, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	refresh()


func set_targetable(on: bool) -> void:
	_targetable = on
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	refresh()


func _gui_input(event: InputEvent) -> void:
	if _targetable and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(player.seat)


func refresh() -> void:
	if player == null:
		return
	var mine := player.seat == 0 and not player.is_bot  # seat 0 is always you
	var idle_border := MINE_BORDER if mine else UiStyle.BRASS
	var border := TARGET if _targetable else (UiStyle.ACTIVE if _active else idle_border)
	var bg := (MINE_BG if mine else Color(UiStyle.WOOD_DARK, 0.92)) if player.alive else Color(0.1, 0.08, 0.07, 0.85)
	var style := UiStyle.panel(bg, border, 3 if (_active or _targetable or mine) else 2, 8)
	style.set_content_margin_all(5)
	if _active or _targetable:
		style.shadow_color = Color(border, 0.35)
		style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	_name_label.text = player.display_name + ("" if player.alive else " (ตกรอบ)")
	_name_label.add_theme_color_override("font_color", UiStyle.ACTIVE if _active else UiStyle.TEXT)
	_fill_pips(_hp_pips, player.hp, hp_max, UiStyle.HP)
	_fill_pips(_ring_pips, player.rings, rings_max, UiStyle.RING)
	_cards_label.text = str(player.hand.size())
	_shards_label.text = str(player.shards)
	tooltip_text = "%s · เงิน %d · เศษแหวน %d · การ์ด %d ใบ" % [player.display_name, player.gold,
		player.shards, player.hand.size()] if not mine else ""
	_fill_status_bar()
	# the player whose turn it is stands out; everyone else is slightly dimmed
	if not player.alive:
		modulate = Color(1, 1, 1, 0.55)
	elif _active or _targetable:
		modulate = Color.WHITE
	else:
		modulate = Color(0.82, 0.82, 0.82)


## Effects as small icons in the card's top-right corner, each with its count (turns left,
## or stacks for a free block) in the corner; name and the same in the tooltip.
func _fill_status_bar() -> void:
	for child in _status_bar.get_children():
		_status_bar.remove_child(child)
		child.queue_free()
	var ids: Array = player.statuses.keys()
	for k in ids.size():
		var id: String = ids[k]
		var turns: int = player.statuses[id]
		var chip := PanelContainer.new()
		if k == MAX_CHIPS - 1 and ids.size() > MAX_CHIPS:
			# no room for more: one "+n" chip listing the rest
			var more := Label.new()
			more.text = "+%d" % (ids.size() - k)
			more.add_theme_font_size_override("font_size", 9)
			chip.add_child(more)
			chip.tooltip_text = ", ".join(ids.slice(k).map(func(i: String) -> String: return GameController.STATUS_NAMES[i]))
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			chip.add_theme_stylebox_override("panel", UiStyle.panel(Color("4a3a5a"), UiStyle.TEXT_DIM, 1, 9))
			_status_bar.add_child(chip)
			break
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(19, 12)  # icon + its count
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(slot)
		slot.add_child(Icons.rect(id, 12))
		var count := Label.new()
		count.text = str(turns)
		count.position = Vector2(10, 1)
		count.size = Vector2(9, 12)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_font_size_override("font_size", 11)
		count.add_theme_color_override("font_color", Color.WHITE)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 3)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count)
		var name: String = GameController.STATUS_NAMES[id]
		match id:
			"bad_luck":
				chip.tooltip_text = "%s: ใช้ผลตอนทอยลูกเต๋าครั้งถัดไป" % name
			"free_block":
				chip.tooltip_text = "%s: ใช้การ์ดป้องกันได้โดยการ์ดไม่หาย %d ครั้ง" % [name, turns]
			_:
				chip.tooltip_text = "%s: เหลือ %d เทิร์น" % [name, turns]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		# curses are purple; good effects (truce, free block) are blue
		var bg := Color("2e86c1") if id in GameController.BUFFS else Color("7d3c98")
		var style := UiStyle.panel(bg, bg.lightened(0.35), 1, 9)
		style.set_content_margin_all(1)
		chip.add_theme_stylebox_override("panel", style)
		_status_bar.add_child(chip)


func _stat_row(parent: Container, caption: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(22, 0)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", color.lightened(0.3))
	row.add_child(label)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 2)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pips)
	return pips


## A small icon + number at the end of a stat row (hand size, shards).
func _count(row: Node, icon_id: String) -> Label:
	row.add_child(Icons.rect(icon_id, 11))
	var label := Label.new()
	label.custom_minimum_size = Vector2(9, 0)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UiStyle.TEXT)
	row.add_child(label)
	return label


func _fill_pips(pips: HBoxContainer, value: int, max_value: int, color: Color) -> void:
	while pips.get_child_count() < max_value:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(7, 7)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	for i in max_value:
		(pips.get_child(i) as ColorRect).color = color if i < value else UiStyle.EMPTY
