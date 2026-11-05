class_name ResultPanel
extends Control
## End of the game, after the user's end-screen mockup: a menu on the left (summary, score
## details, what everyone had left, main menu), the winner's card with their character in 3D,
## everyone's ranked cards under it, your own stats at the bottom, and on the right: play
## again in the same room (reloads the table with the same seats), find a new room, main menu.

const MENU_SCENE := "res://menu.tscn"
## Score shown on the cards (rank is still winner first, then standings()).
const SCORE := {"rings": 100, "shards": 20, "kills": 50, "damage": 10, "hp": 5, "win": 300}

var _game: GameController
var _winner := -1
var _pages: Dictionary = {}  # tab -> Control
var _tabs: Dictionary = {}  # tab -> Button
var _again: Button
var _narrow_cells := false  # 5-6 players: smaller score-table cells


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var left := MenuUi.panel(Vector2(14, 14), Vector2(164, 512))
	add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 8)
	left.add_child(lbox)
	var head := MenuUi.label("จบเกม", 26, MenuUi.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_outline_color", Color("2a1408"))
	head.add_theme_constant_override("outline_size", 6)
	lbox.add_child(head)
	lbox.add_child(HSeparator.new())
	var group := ButtonGroup.new()
	for t: Array in [["summary", "สรุปผล"], ["score", "รายละเอียดคะแนน"], ["items", "ของที่เหลือ"]]:
		var b := MenuUi.choice_button(t[1], group, t[0] == "summary")
		b.custom_minimum_size = Vector2(136, 40)
		b.pressed.connect(_show_page.bind(t[0]))
		lbox.add_child(b)
		_tabs[t[0]] = b
	var home := MenuUi.small_button("กลับหน้าหลัก", "", 136)
	home.custom_minimum_size.y = 40
	home.pressed.connect(_to_menu.bind("home"))
	lbox.add_child(home)

	var full := ScreenMode.button()  # top right, in from the edges like the left panel
	full.position = Vector2(960 - 14 - 44, 14)
	add_child(full)

	var right := VBoxContainer.new()
	right.position = Vector2(782, 236)
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	var again := MenuUi.big_button("swords", "เล่นต่อ", "", true, 164)
	_again = again
	again.pressed.connect(func() -> void:
		if NetPlay.node().online():  # the same room again: back to its lobby
			if NetPlay.node().is_host():
				NetPlay.node().back_to_lobby()
			MainMenu.start_screen = "lobby"
			get_tree().change_scene_to_file(MENU_SCENE)
		else:
			get_tree().reload_current_scene())
	right.add_child(again)
	var find := MenuUi.big_button("cards", "ค้นหาห้องใหม่", "", false, 164)
	find.pressed.connect(_to_menu.bind("find"))
	right.add_child(find)
	var menu := MenuUi.big_button("", "กลับหน้าหลัก", "", false, 164)
	menu.pressed.connect(_to_menu.bind("home"))
	right.add_child(menu)
	var quit := MenuUi.small_button("ออกจากเกม", "", 164)
	quit.pressed.connect(func() -> void:  # through the sound player, so it quits cleanly
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	right.add_child(quit)


## Winner first, then the living by rings, shards and HP, then those knocked out.
static func standings(game: GameController, winner: int) -> Array[PlayerData]:
	var out: Array[PlayerData] = game.players.duplicate()
	if game.watching:
		out.pop_front()  # the spectator's own place
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		if (a.seat == winner) != (b.seat == winner):
			return a.seat == winner
		if a.alive != b.alive:
			return a.alive
		if a.rings != b.rings:
			return a.rings > b.rings
		if a.shards != b.shards:
			return a.shards > b.shards
		return a.hp > b.hp)
	return out


## [label, count, points] per scoring line.
static func score_parts(p: PlayerData, winner: int) -> Array:
	return [["แหวน", p.rings, p.rings * SCORE["rings"]], ["เศษแหวน", p.shards, p.shards * SCORE["shards"]],
		["สังหาร", p.kills, p.kills * SCORE["kills"]], ["ดาเมจ", p.damage, p.damage * SCORE["damage"]],
		["เลือดที่เหลือ", p.hp, p.hp * SCORE["hp"]], ["ชนะ", 1 if p.seat == winner else 0, SCORE["win"] if p.seat == winner else 0]]


static func score(p: PlayerData, winner: int) -> int:
	var total := 0
	for part: Array in score_parts(p, winner):
		total += part[2]
	return total


func show_result(game: GameController, winner: int) -> void:
	_game = game
	_winner = winner
	for page: Control in _pages.values():
		page.queue_free()
	_pages = {"summary": _build_summary(), "score": _build_score(), "items": _build_items()}
	for page: Control in _pages.values():
		add_child(page)
	_tabs["summary"].button_pressed = true
	_show_page("summary")
	_again.visible = not game.watching  # a spectator has no place at the table
	move_to_front()
	z_index = 100  # over the table HUD (turn-order badges and hand cards use z_index)
	visible = true


func _show_page(tab: String) -> void:
	for k: String in _pages:
		_pages[k].visible = k == tab


func _to_menu(screen: String) -> void:
	NetPlay.node().leave()
	MainMenu.start_screen = screen
	get_tree().change_scene_to_file(MENU_SCENE)


func _page() -> Control:
	var c := Control.new()
	c.position = Vector2(190, 14)
	c.size = Vector2(580, 512)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _status(p: PlayerData) -> String:
	return "ชนะ" if p.seat == _winner else ("รอด" if p.alive else "ตกรอบ")


func _character_name(p: PlayerData) -> String:
	return CharacterDB.get_character(p.character).get("name", p.character)


# ---------- summary ----------

func _build_summary() -> Control:
	var page := _page()
	var w := _game.players[_winner]
	var top := MenuUi.panel(Vector2.ZERO, Vector2(580, 226), MenuUi.GOLD)
	page.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	top.add_child(row)
	row.add_child(CharacterPreview.new(w.character, Vector2(180, 196), false))
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var rank := MenuUi.label("อันดับที่ 1", 34, MenuUi.GOLD)
	rank.add_theme_color_override("font_outline_color", Color("2a1408"))
	rank.add_theme_constant_override("outline_size", 8)
	info.add_child(rank)
	info.add_child(MenuUi.label(("คุณชนะ!  " if _game.is_me(w) else "") + w.display_name, 22, UiStyle.TEXT))
	if _character_name(w) != w.display_name:
		info.add_child(MenuUi.label(_character_name(w), 14, UiStyle.TEXT_DIM))
	var reason := MenuUi.label(_game.win_reason, 13, UiStyle.TEXT_DIM)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.custom_minimum_size = Vector2(340, 0)
	info.add_child(reason)
	var total := HBoxContainer.new()
	total.add_theme_constant_override("separation", 8)
	info.add_child(total)
	total.add_child(MenuUi.label("คะแนนรวม", 16, MenuUi.GOLD))
	total.add_child(MenuUi.label(str(score(w, _winner)), 28, MenuUi.GOLD))
	info.add_child(MenuUi.label("เล่นไป %d รอบ · มินิเกม %d ครั้ง" % [_game.round_no, _game.minigames_played], 12, UiStyle.TEXT_DIM))

	var cards := HBoxContainer.new()
	cards.position = Vector2(0, 236)
	cards.custom_minimum_size = Vector2(580, 0)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	page.add_child(cards)
	var ranked := standings(_game, _winner)
	var cw := minf(160.0, (580.0 - (ranked.size() - 1) * 10.0) / ranked.size())
	for i in ranked.size():
		cards.add_child(_rank_card(ranked[i], i + 1, cw))

	if not _game.watching:
		page.add_child(_my_stats())
	return page


func _rank_card(p: PlayerData, place: int, w: float) -> PanelContainer:
	var me := _game.is_me(p)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(w, 0)
	var border := MenuUi.GOLD if place == 1 else (Color("4f8fd6") if me else MenuUi.GOLD_DARK)
	var s := UiStyle.panel(Color("1d2a3c") if me else Color("21160e"), border, 2, 8)
	s.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", s)
	if not p.alive and p.seat != _winner:
		card.modulate = Color(0.75, 0.72, 0.7)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(MenuUi.label("#%d" % place, 18, MenuUi.GOLD if place == 1 else UiStyle.TEXT))
	var st := MenuUi.label(_status(p), 12, MenuUi.GOLD if p.seat == _winner else (Color("7fc97f") if p.alive else Color("e07a6a")))
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(st)
	box.add_child(CharacterPreview.new(p.character, Vector2(w - 12, 70.0 if w < 120.0 else 92.0), false))
	var name := MenuUi.label(("★ " if me else "") + p.display_name, 14, MenuUi.GOLD if me else UiStyle.TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	box.add_child(name)
	var ch := MenuUi.label(_character_name(p) + ("" if me else " · บอท"), 11, UiStyle.TEXT_DIM)
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.clip_text = true
	box.add_child(ch)
	var narrow := w < 120.0  # 5-6 players
	var sc := MenuUi.label("%d คะแนน" % score(p, _winner), 13 if narrow else 15, MenuUi.GOLD)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sc)
	var stats := HFlowContainer.new()  # HP and rings side by side, or stacked on a narrow card
	stats.alignment = FlowContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("h_separation", 4)
	box.add_child(stats)
	stats.add_child(MenuUi.label("♥ %d/%d" % [p.hp, _game.max_hp], 12, UiStyle.HP.lightened(0.25)))
	if _game.rings_to_win > 0:  # rings off: HP only
		stats.add_child(Icons.rect("ring", 14))
		stats.add_child(MenuUi.label("%d/%d" % [p.rings, _game.rings_to_win], 12, UiStyle.RING))
	return card


func _my_stats() -> PanelContainer:
	var me: PlayerData = _game.players[0]
	var p := MenuUi.panel(Vector2(0, 432), Vector2(580, 80))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	p.add_child(row)
	var title := MenuUi.label("ผลงานของคุณ", 14, MenuUi.GOLD)
	row.add_child(title)
	for s: Array in [["สังหาร", me.kills], ["ตาย", 0 if me.alive else 1], ["ช่วยเหลือ", me.helps],
			["ดาเมจ", me.damage], ["เงิน", me.gold]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		row.add_child(col)
		var v := MenuUi.label(str(s[1]), 22, UiStyle.TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(v)
		var l := MenuUi.label(s[0], 11, UiStyle.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	return p


# ---------- score details ----------

func _build_score() -> Control:
	var page := _page()
	var p := MenuUi.panel(Vector2.ZERO, Vector2(580, 512))
	page.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	box.add_child(MenuUi.label("รายละเอียดคะแนน", 20, MenuUi.GOLD))
	var ranked := standings(_game, _winner)
	_narrow_cells = ranked.size() > 4
	var grid := GridContainer.new()
	grid.columns = ranked.size() + 1
	grid.add_theme_constant_override("h_separation", 8 if _narrow_cells else 22)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	grid.add_child(MenuUi.label("", 14))
	for q in ranked:
		grid.add_child(_cell(q.display_name, MenuUi.GOLD if _game.is_me(q) else UiStyle.TEXT))
	var lines: Array = score_parts(ranked[0], _winner)
	for i in lines.size():
		var each: int = SCORE.values()[i]
		grid.add_child(MenuUi.label("%s (×%d)" % [lines[i][0], each] if lines[i][0] != "ชนะ" else "โบนัสผู้ชนะ",
			12 if _narrow_cells else 14, UiStyle.TEXT_DIM))
		for q in ranked:
			var part: Array = score_parts(q, _winner)[i]
			var arrow := "→" if _narrow_cells else "  →  "
			grid.add_child(_cell("%d%s%d" % [part[1], arrow, part[2]] if part[0] != "ชนะ" else str(part[2]), UiStyle.TEXT))
	grid.add_child(MenuUi.label("รวม", 16, MenuUi.GOLD))
	for q in ranked:
		grid.add_child(_cell(str(score(q, _winner)), MenuUi.GOLD, 18))
	var note := MenuUi.label("อันดับ: ผู้ชนะก่อน แล้วคนที่รอดเรียงตามแหวน เศษแหวน และเลือด แล้วคนที่ตกรอบ", 12, UiStyle.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return page


func _cell(text: String, color: Color, size := 14) -> Label:
	var l := MenuUi.label(text, size - 2 if _narrow_cells else size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(60 if _narrow_cells else 80, 0)
	l.clip_text = true
	return l


# ---------- what everyone had left ----------

func _build_items() -> Control:
	var page := _page()
	var p := MenuUi.panel(Vector2.ZERO, Vector2(580, 512))
	page.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	box.add_child(MenuUi.label("ของที่เหลือตอนจบเกม", 20, MenuUi.GOLD))
	for q in standings(_game, _winner):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var name := MenuUi.label(q.display_name, 15, MenuUi.GOLD if _game.is_me(q) else UiStyle.TEXT)
		name.custom_minimum_size = Vector2(130, 0)
		name.clip_text = true
		row.add_child(name)
		if _game.rings_to_win > 0:
			row.add_child(Icons.rect("ring", 18))
			row.add_child(MenuUi.label(str(q.rings), 14, UiStyle.RING))
			row.add_child(Icons.rect("shard", 18))
			row.add_child(MenuUi.label(str(q.shards), 14))
		row.add_child(MenuUi.label("เงิน %d" % q.gold, 14, UiStyle.ACTIVE))
		var hand := HBoxContainer.new()
		hand.add_theme_constant_override("separation", 2)
		row.add_child(hand)
		if q.hand.is_empty():
			hand.add_child(MenuUi.label("ไม่มีการ์ด", 12, UiStyle.TEXT_DIM))
		for c: Dictionary in q.hand:
			var ic := Icons.rect(_game.card_icon(q, c), 24)
			ic.tooltip_text = c.get("name", "")
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			hand.add_child(ic)
	return page
