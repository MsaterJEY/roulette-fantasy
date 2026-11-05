class_name MainMenu
extends Control
## The menus, after the user's interface mockup: main menu over the tavern, Create Room (the
## room settings), the lobby (pick your character, the bots take their seats, start), and Find
## Room / Join by Code, which show what online play will look like (not built yet: the game is
## you against bots). Settings (name, volume) and How to Play open over any screen.
## Headless runs (smoke tests) go straight to the table.

const TABLE_SCENE := "res://main.tscn"
const W := 960.0

## Which screen opens first: the results screen's "ค้นหาห้องใหม่" sets "find".
static var start_screen := "home"
## A message to show when the menu opens (e.g. why an online game ended).
static var notice := ""

var sfx: Sfx
var _screens: Dictionary = {}  # name -> Control
var _modal: Control
var _toast: PanelContainer
var _toast_label: Label
var _badge_name: Label

# Create Room
var _room_name: LineEdit
var _summary: Label
var _sections: VBoxContainer
var _open_sections: Dictionary = {}  # section key -> open
var _preset_buttons: Dictionary = {}  # preset id -> Button
var _rings_before := 5  # rings to win before minigames were turned off

# lobby
var _lobby_title: Label
var _lineup: HBoxContainer
var _players_box: VBoxContainer
var _players_head: Label
var _pick_buttons: Dictionary = {}  # character id -> Button
var _pick_info: Label
var _chat_log: RichTextLabel
## Ready check: everyone presses Ready (the bots after a moment); then the host starts, or in
## "auto" rooms a countdown starts the game by itself.
const AUTO_START_SECONDS := 3.0
const FIND_REFRESH_SECONDS := 3.0
var _find_refresh := 0.0
var _room_rows: VBoxContainer
var _room_stats: Label
var _room_empty: Label
var _ready_btn: Button
var _start_btn: Button
var _lobby_gen := 0  # bumped on each lobby entry, so old bot timers do nothing
var _countdown := -1.0  # auto start: seconds left, -1 = not counting
var _starting := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred(TABLE_SCENE)
		return
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameConfig.load_settings()
	sfx = Sfx.new()
	add_child(sfx)

	var scene := MenuScene.new()  # the four heroes playing round the table
	scene.size = Vector2(W, 540)
	add_child(scene)
	var ids := CharacterDB.ids()
	ids.shuffle()
	scene.seat_all(ids)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.15)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_screens["home"] = _build_home()
	_screens["find"] = _build_find()
	_screens["join"] = _build_join()
	_screens["create"] = _build_create()
	_screens["lobby"] = _build_lobby()
	for s: Control in _screens.values():
		add_child(s)
	_build_badge()
	_build_toast()
	NetPlay.node().lobby_changed.connect(_render_lobby)
	NetPlay.node().chat.connect(func(b: String) -> void: _chat(b))
	NetPlay.node().rooms_listed.connect(_fill_rooms)
	NetPlay.node().room_stats.connect(_show_room_stats)
	NetPlay.node().joined.connect(func() -> void:
		toast("เข้าห้องแล้ว")
		show_screen("lobby"))
	NetPlay.node().failed.connect(func(why: String) -> void:
		toast(why)
		if _screens["lobby"].visible:
			NetPlay.node().seats.clear()
			show_screen("home"))
	show_screen(start_screen)
	start_screen = "home"
	if notice != "":
		toast(notice)
		notice = ""


func _exit_tree() -> void:
	Icons.clear()
	PixelTex.clear()


func show_screen(screen: String) -> void:
	for k: String in _screens:
		_screens[k].visible = k == screen
	if screen == "lobby":
		_enter_lobby()
	elif screen == "find":
		_find_refresh = 0.0


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _title(parent: Control, text: String) -> void:
	var t := MenuUi.title(text)
	t.position = Vector2(0, 14)
	parent.add_child(t)
	t.resized.connect(func() -> void: t.position.x = (W - t.size.x) / 2)


func _back(parent: Control, to := "home", text := "กลับ") -> Button:
	var b := MenuUi.small_button("  ◀  " + text + "  ", "", 120)
	b.position = Vector2(20, 488)
	b.pressed.connect(show_screen.bind(to))
	parent.add_child(b)
	return b


# ---------- main menu ----------

func _build_home() -> Control:
	var s := _screen()
	var logo_plate := PanelContainer.new()
	logo_plate.add_theme_stylebox_override("panel", MenuUi.panel_style(MenuUi.GOLD_DARK, 2, MenuUi.DIM))
	logo_plate.position = Vector2(48, 34)
	logo_plate.custom_minimum_size = Vector2(300, 0)
	s.add_child(logo_plate)
	var lbox := VBoxContainer.new()
	logo_plate.add_child(lbox)
	lbox.add_child(MenuUi.logo(44))

	var col := VBoxContainer.new()
	col.position = Vector2(83, 200)
	col.add_theme_constant_override("separation", 12)
	s.add_child(col)
	# the buttons sit just under the logo, whatever height the font gives it (taller on the web)
	logo_plate.resized.connect(func() -> void:
		col.position.y = maxf(190.0, logo_plate.position.y + logo_plate.size.y + 20.0))
	var create := MenuUi.big_button("swords", "สร้างห้อง", "", true)
	create.pressed.connect(func() -> void:
		sfx.play("select")
		show_screen("create"))
	col.add_child(create)
	var find := MenuUi.big_button("cards", "ค้นหาห้อง", "")
	find.pressed.connect(show_screen.bind("find"))
	col.add_child(find)
	var join := MenuUi.big_button("dice", "ใส่เลขห้อง", "")
	join.pressed.connect(show_screen.bind("join"))
	col.add_child(join)

	var row := HBoxContainer.new()  # centred under the logo plate (the web has no Quit)
	row.position = Vector2(48, 452)
	row.custom_minimum_size = Vector2(300, 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	s.add_child(row)
	var settings := MenuUi.small_button(" ตั้งค่า ", "", 94)
	settings.pressed.connect(_open_settings)
	row.add_child(settings)
	var howto := MenuUi.small_button(" วิธีเล่น ", "", 94)
	howto.pressed.connect(_open_howto)
	row.add_child(howto)
	var quit := MenuUi.small_button(" ออกจากเกม ", "", 94)
	quit.pressed.connect(func() -> void:  # through the sound player, so it quits cleanly
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	row.add_child(quit)
	quit.visible = not OS.has_feature("web")  # a browser tab can't be closed by the page

	var ver := MenuUi.label("v0.3", 11, UiStyle.TEXT_DIM)
	ver.position = Vector2(W - 20, 512)  # right edge in line with the full screen button (above)
	ver.resized.connect(func() -> void: ver.position.x = W - 20 - ver.size.x)
	s.add_child(ver)
	return s


# ---------- find room / join by code ----------

func _build_find() -> Control:
	var s := _screen()
	_title(s, "ค้นหาห้อง")
	var p := MenuUi.panel(Vector2(130, 74), Vector2(700, 380))
	s.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	for h: Array in [["ชื่อห้อง", 300], ["ผู้เล่น", 120], ["แหวน", 100], ["สถานะ", 120]]:
		var l := MenuUi.label(h[0], 14, MenuUi.GOLD)
		l.custom_minimum_size = Vector2(h[1], 0)
		head.add_child(l)
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_room_rows = VBoxContainer.new()
	_room_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_room_rows)
	_room_empty = MenuUi.label("", 15, UiStyle.TEXT_DIM)
	_room_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_room_empty)
	_fill_rooms([])
	var go := MenuUi.big_button("swords", "สร้างห้องแทน", "", true, 210)
	go.position = Vector2(W - 230, 473)  # level with Back (488-522)
	go.pressed.connect(show_screen.bind("create"))
	s.add_child(go)
	_back(s)
	_room_stats = MenuUi.label("", 14, MenuUi.GOLD)  # who's around: online play only
	_room_stats.position = Vector2(0, 488)
	_room_stats.size = Vector2(W, 34)
	_room_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_stats.add_theme_color_override("font_outline_color", Color("2a1408"))
	_room_stats.add_theme_constant_override("outline_size", 5)
	s.add_child(_room_stats)
	return s


func _build_join() -> Control:
	var s := _screen()
	_title(s, "ใส่เลขห้อง")
	var p := MenuUi.panel(Vector2(250, 120), Vector2(460, 270))
	s.add_child(p)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	var hint := MenuUi.label("กรอกเลขห้อง 6 หลักที่เพื่อนส่งมา", 16, UiStyle.TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var code := LineEdit.new()
	code.max_length = 6
	MenuUi.keyboard_limit(code)
	code.placeholder_text = "000000"
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.custom_minimum_size = Vector2(260, 58)
	code.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	code.add_theme_font_size_override("font_size", 34)
	code.add_theme_color_override("font_color", MenuUi.GOLD)
	code.add_theme_stylebox_override("normal", UiStyle.panel(Color("120c08"), MenuUi.GOLD_DARK, 2, 8))
	code.add_theme_stylebox_override("focus", UiStyle.panel(Color("120c08"), MenuUi.GOLD, 2, 8))
	code.text_changed.connect(func(t: String) -> void:  # digits only
		var digits := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != t:
			code.text = digits
			code.caret_column = digits.length())
	box.add_child(code)
	var join := MenuUi.big_button("", "เข้าร่วมห้อง", "", true, 200)
	join.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join.pressed.connect(func() -> void:
		if code.text.length() < 6:
			toast("เลขห้องต้องมี 6 หลัก")
		else:
			_join(code.text))
	code.text_submitted.connect(func(_t: String) -> void: join.pressed.emit())
	box.add_child(join)
	var note := MenuUi.label("ห้องที่มีรหัสผ่าน จะถามรหัส 4 หลักหลังกดเข้าร่วม", 12, UiStyle.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	_back(s)
	return s


func _show_room_stats(online: int, playing: int) -> void:
	_room_stats.text = "ออนไลน์ %d คน · เล่นอยู่ %d ห้อง" % [online, playing]


## The open rooms from the room API, each with a Join button.
func _fill_rooms(rooms: Array) -> void:
	if _room_rows == null:
		return
	for child in _room_rows.get_children():
		child.queue_free()
	for r: Dictionary in rooms:
		var row := HBoxContainer.new()
		var cells := [[("🔒 " if r.get("locked") else "") + str(r.get("name", "")), 300],
			["%d/%d" % [int(r.get("count", 1)), int(r.get("max", 4))], 120],
			[str(int(r.get("rings", 0))) + " วง" if int(r.get("rings", 0)) > 0 else "ไม่ใช้", 100]]
		for c: Array in cells:
			var l := MenuUi.label(c[0], 14)
			l.custom_minimum_size = Vector2(c[1], 0)
			l.clip_text = true
			row.add_child(l)
		var go := MenuUi.small_button("  เข้าร่วม  ", "", 100)
		go.pressed.connect(_join.bind(str(r.get("code", ""))))
		row.add_child(go)
		_room_rows.add_child(row)
	if not NetPlay.node().available():
		_room_empty.text = "เล่นออนไลน์ได้บนเว็บของเกม
เวอร์ชันนี้เล่นกับบอทได้ที่ \"สร้างห้อง\""
	elif rooms.is_empty():
		_room_empty.text = "ยังไม่มีห้องเปิดอยู่
สร้างห้องเอง แล้วส่งเลขห้องให้เพื่อน"
	else:
		_room_empty.text = ""
	_room_empty.visible = _room_empty.text != ""


## Join room `room_code` (asking for its password if it has one).
func _join(room_code: String, password := "") -> void:
	if not NetPlay.node().available():
		toast("เล่นออนไลน์ได้บนเว็บของเกม")
		return
	toast("กำลังเชื่อมต่อห้อง %s..." % room_code)
	NetPlay.node().seats.clear()
	var on_fail := func(why: String) -> void:
		if why == NetPlay.WRONG_PASSWORD or why == NetPlay.NEED_PASSWORD:
			_ask_password(room_code, why == NetPlay.WRONG_PASSWORD and password != "")
	NetPlay.node().failed.connect(on_fail, CONNECT_ONE_SHOT)
	NetPlay.node().joined.connect(func() -> void:
		if NetPlay.node().failed.is_connected(on_fail):
			NetPlay.node().failed.disconnect(on_fail), CONNECT_ONE_SHOT)
	NetPlay.node().join(room_code, password)


func _ask_password(room_code: String, wrong: bool) -> void:
	var box := _open_modal("รหัสผ่านห้อง", Vector2(360, 200))
	if wrong:
		box.add_child(MenuUi.label("รหัสไม่ถูกต้อง ลองใหม่", 13, Color("ff8a7a")))
	var pw := LineEdit.new()
	pw.max_length = 4
	MenuUi.keyboard_limit(pw)
	pw.placeholder_text = "0000"
	pw.alignment = HORIZONTAL_ALIGNMENT_CENTER
	pw.custom_minimum_size = Vector2(160, 44)
	pw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pw.add_theme_font_size_override("font_size", 24)
	box.add_child(pw)
	var ok := MenuUi.small_button("  เข้าร่วม  ", "", 120)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		_close_modal()
		_join(room_code, pw.text))
	pw.text_submitted.connect(func(_t: String) -> void: ok.pressed.emit())
	box.add_child(ok)
	pw.grab_focus.call_deferred()


# ---------- create room ----------
# Presets on top (most players pick one and go), then the settings in folding sections, like
# the user's design: room, match rules, minigame. The summary and
# the Create button on the right.

func _build_create() -> Control:
	var s := _screen()
	_title(s, "สร้างห้อง")
	var pre := MenuUi.panel(Vector2(30, 62), Vector2(600, 96))
	s.add_child(pre)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	pre.add_child(prow)
	var group := ButtonGroup.new()
	for id: String in GameConfig.PRESETS:
		var info: Dictionary = GameConfig.PRESETS[id]
		var b := MenuUi.choice_button("", group, GameConfig.preset == id)
		b.custom_minimum_size = Vector2(137, 66)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", -2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(top)
		top.add_child(Icons.rect(info["icon"], 20))
		top.add_child(MenuUi.label(info["name"], 15, UiStyle.TEXT))
		var d := MenuUi.label(info["desc"], 10, UiStyle.TEXT_DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(128, 0)
		box.add_child(d)
		b.pressed.connect(_choose_preset.bind(id))
		prow.add_child(b)
		_preset_buttons[id] = b

	var form := MenuUi.panel(Vector2(30, 166), Vector2(600, 312))
	s.add_child(form)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form.add_child(scroll)
	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 2)
	scroll.add_child(_sections)

	var sp := MenuUi.panel(Vector2(642, 62), Vector2(288, 416), MenuUi.GOLD)
	s.add_child(sp)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 8)
	sp.add_child(sbox)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	sbox.add_child(head)
	head.add_child(Icons.rect("star", 20))
	head.add_child(MenuUi.label("สรุปก่อนสร้างห้อง", 17, MenuUi.GOLD))
	sbox.add_child(HSeparator.new())
	_summary = MenuUi.label("", 14)
	_summary.add_theme_constant_override("line_spacing", 2)
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sbox.add_child(_summary)
	var go := MenuUi.big_button("swords", "สร้างห้อง", "", true, 258)
	go.pressed.connect(_create_room)
	sbox.add_child(go)
	_back(s)
	_fill_sections()
	return s


## (Re)build the folding sections from GameConfig; open ones stay open.
func _fill_sections() -> void:
	for c in _sections.get_children():
		c.queue_free()
	var room := _section("room", "cards", "ตั้งค่าห้อง")
	_room_name = LineEdit.new()
	_room_name.text = GameConfig.room_name
	_room_name.max_length = 24
	MenuUi.keyboard_limit(_room_name)
	_room_name.custom_minimum_size = Vector2(300, 34)
	_room_name.add_theme_stylebox_override("normal", UiStyle.panel(Color("120c08"), MenuUi.GOLD_DARK, 1, 6))
	_room_name.text_changed.connect(func(t: String) -> void:
		GameConfig.room_name = t.strip_edges()
		_update_summary())
	_setting(room, "ชื่อห้อง", _room_name)
	_setting(room, "จำนวนผู้เล่น", _choices([["2 คน", 2], ["3 คน", 3], ["4 คน", 4], ["5 คน", 5], ["6 คน", 6]], GameConfig.players,
		func(v: int) -> void: GameConfig.players = v))

	var rules := _section("rules", "swords", "กติกา")
	_setting(rules, "เวลาต่อเทิร์น", _choices([["15 วิ", 15], ["20 วิ", 20], ["30 วิ", 30], ["45 วิ", 45]],
		GameConfig.turn_seconds, func(v: int) -> void: GameConfig.turn_seconds = v))
	var rings := _choices([["3 วง", 3], ["5 วง", 5], ["7 วง", 7], ["ไม่ใช้แหวน", 0]], GameConfig.rings_to_win,
		func(v: int) -> void: GameConfig.rings_to_win = v)
	if not GameConfig.minigames:  # no minigame, no shards: rings can't be won
		for b: Button in rings.get_children():
			b.disabled = true
			b.tooltip_text = "เปิดมินิเกมก่อน (เศษแหวนได้จากมินิเกม)"
			if b.button_pressed:  # still show which one is on
				b.add_theme_stylebox_override("disabled", UiStyle.panel(Color("5a4220"), MenuUi.GOLD_DARK, 2, 8))
	_setting(rules, "ชนะเมื่อได้แหวน", rings)
	rules.add_child(_note("คนสุดท้ายที่รอดชนะเสมอ · ทุก %d รอบ เลือดและการ์ดในมือสูงสุด -1" % GameController.SHRINK_ROUNDS))

	var mini := _section("minigame", "dice", "มินิเกม")
	_setting(mini, "มินิเกม", _choices([["เปิด", 1], ["ปิด", 0]], 1 if GameConfig.minigames else 0,
		func(v: int) -> void: _set_minigames(v == 1)))
	mini.add_child(_note("มินิเกมเป็นทางเดียวที่ได้เศษแหวน · ปิด = ไม่ใช้แหวน"))

	_update_summary()


## A folding section: a header (icon, title, ▼) that opens a body.
func _section(key: String, icon: String, title: String) -> VBoxContainer:
	var head := Button.new()
	head.flat = true
	head.custom_minimum_size = Vector2(0, 54)
	head.add_theme_stylebox_override("hover", UiStyle.panel(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 6))
	head.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_sections.add_child(head)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -10
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(row)
	var ic := Icons.rect(icon, 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -3)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	texts.add_child(MenuUi.label(title, 16, UiStyle.TEXT))
	var arrow := MenuUi.label("", 13, MenuUi.GOLD)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 42)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.add_child(body)
	_sections.add_child(pad)
	var line := HSeparator.new()
	line.modulate = Color(1, 1, 1, 0.4)
	_sections.add_child(line)
	var show_body := func(open: bool) -> void:
		pad.visible = open
		arrow.text = "▲" if open else "▼"
		_open_sections[key] = open
	show_body.call(_open_sections.get(key, false))
	head.pressed.connect(func() -> void: show_body.call(not pad.visible))
	return body


## A label + control row inside a section; returns the row.
func _setting(body: VBoxContainer, text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := MenuUi.label(text, 14, MenuUi.GOLD)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	row.add_child(control)
	body.add_child(row)
	return row


## A label + control pair in a two-column grid (the Settings box).
func _form_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := MenuUi.label(text, 16, MenuUi.GOLD)
	l.custom_minimum_size = Vector2(150, 0)
	grid.add_child(l)
	grid.add_child(control)


func _note(text: String) -> Label:
	var l := MenuUi.label(text, 12, UiStyle.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	return l


## A row of toggles; `on_pick(value)` when one is chosen (the room becomes "custom").
func _choices(options: Array, current: int, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for o: Array in options:
		var b := MenuUi.choice_button(o[0], group, o[1] == current)
		var chars := (o[0] as String).length()
		b.custom_minimum_size = Vector2(130.0 if chars > 8 else (90.0 if chars > 4 else 66.0), 32)
		b.pressed.connect(func() -> void:
			on_pick.call(o[1])
			_mark_custom())
		row.add_child(b)
	return row


func _choose_preset(id: String) -> void:
	sfx.play("select")
	GameConfig.apply_preset(id)
	_preset_buttons[id].button_pressed = true
	if id == "custom":  # open the settings for those who want the detail
		_open_sections["room"] = true
		_open_sections["rules"] = true
	_fill_sections()


## Minigames on/off. Off also turns rings off (their shards only come from minigames); back
## on brings the rings setting back.
func _set_minigames(on: bool) -> void:
	GameConfig.minigames = on
	if not on and GameConfig.rings_to_win > 0:
		_rings_before = GameConfig.rings_to_win
		GameConfig.rings_to_win = 0
	elif on and GameConfig.rings_to_win == 0:
		GameConfig.rings_to_win = _rings_before
	_fill_sections.call_deferred()  # not now: the pressed button is one of the rows rebuilt


## A setting was changed by hand: the room no longer matches a preset.
func _mark_custom() -> void:
	if GameConfig.preset != "custom":
		GameConfig.preset = "custom"
		_preset_buttons["custom"].button_pressed = true
	_update_summary()


func _update_summary() -> void:
	if _summary == null:
		return
	_summary.text = "\n".join([
		"แบบห้อง: %s" % GameConfig.PRESETS[GameConfig.preset]["name"],
		"ผู้เล่น: %d คน (คุณ + บอท %d)" % [GameConfig.players, GameConfig.players - 1],
		"เวลาต่อเทิร์น: %d วินาที" % GameConfig.turn_seconds,
		"ชนะเมื่อ: แหวน %d วง หรือรอดคนสุดท้าย" % GameConfig.rings_to_win if GameConfig.rings_to_win > 0
			else "ชนะเมื่อ: รอดเป็นคนสุดท้าย (ไม่ใช้แหวน)",
		"มินิเกม: %s" % ("เปิด · ทุก 2 รอบ" if GameConfig.minigames else "ปิด"),
		"ทุก %d รอบ: เลือด/การ์ดในมือสูงสุด -1" % GameController.SHRINK_ROUNDS])



## The room opens: online (in the browser) others can find and join it; the free places are
## the bots'.
func _create_room() -> void:
	sfx.play("confirm")
	if GameConfig.room_name == "":
		GameConfig.room_name = "ห้องของฉัน"
	GameConfig.new_room_code()
	GameConfig.roll_bot_names()
	if NetPlay.node().available():
		toast("กำลังเปิดห้องออนไลน์...")
	NetPlay.node().create_room(_my_char(), func(err: String) -> void:
		if err != "":
			toast(err)
		elif NetPlay.node().online():
			toast("เปิดห้องแล้ว · เลขห้อง %s" % NetPlay.node().code)
		show_screen("lobby"))


# ---------- lobby ----------

func _build_lobby() -> Control:
	var s := _screen()
	var plate := PanelContainer.new()
	var ps := UiStyle.panel(Color(0.07, 0.05, 0.04, 0.92), MenuUi.GOLD_DARK, 1, 14)
	ps.content_margin_left = 22
	ps.content_margin_right = 22
	plate.add_theme_stylebox_override("panel", ps)
	plate.position = Vector2(0, 12)
	s.add_child(plate)
	_lobby_title = MenuUi.label("", 20, MenuUi.GOLD)
	plate.add_child(_lobby_title)
	plate.resized.connect(func() -> void: plate.position.x = (W - plate.size.x) / 2)

	var line := MenuUi.panel(Vector2(20, 60), Vector2(610, 292))
	s.add_child(line)
	_lineup = HBoxContainer.new()
	_lineup.alignment = BoxContainer.ALIGNMENT_CENTER
	_lineup.add_theme_constant_override("separation", 10)
	line.add_child(_lineup)

	var pick := MenuUi.panel(Vector2(20, 362), Vector2(610, 112))
	s.add_child(pick)
	line.resized.connect(func() -> void: pick.custom_minimum_size.x = line.size.x)  # the line-up can widen it
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 6)
	pick.add_child(pbox)
	pbox.add_child(MenuUi.label("เลือกตัวละครของคุณ", 14, MenuUi.GOLD))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	pbox.add_child(prow)
	var group := ButtonGroup.new()
	for c: Dictionary in CharacterDB.all():
		var b := MenuUi.choice_button(" " + c["name"], group, false)
		b.icon = Icons.get_icon(c["icon"])
		b.add_theme_constant_override("icon_max_width", 22)
		b.custom_minimum_size = Vector2(140, 36)
		b.pressed.connect(_pick.bind(c["id"]))
		prow.add_child(b)
		_pick_buttons[c["id"]] = b
	_pick_info = MenuUi.label("", 12, UiStyle.TEXT_DIM)
	pbox.add_child(_pick_info)

	var pl := MenuUi.panel(Vector2(645, 60), Vector2(295, 232))  # room for 6 players
	s.add_child(pl)
	var plbox := VBoxContainer.new()
	plbox.add_theme_constant_override("separation", 6)
	pl.add_child(plbox)
	_players_head = MenuUi.label("", 15, MenuUi.GOLD)
	plbox.add_child(_players_head)
	plbox.add_child(HSeparator.new())
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	plbox.add_child(_players_box)

	var chat := MenuUi.panel(Vector2(645, 300), Vector2(295, 174))
	s.add_child(chat)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 6)
	chat.add_child(cbox)
	cbox.add_child(MenuUi.label("ข้อความในห้อง", 14, MenuUi.GOLD))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override("normal_font_size", 12)
	cbox.add_child(_chat_log)
	var say := LineEdit.new()
	say.placeholder_text = "พิมพ์ข้อความ แล้วกด Enter"
	say.max_length = 60
	MenuUi.keyboard_limit(say)
	say.add_theme_stylebox_override("normal", UiStyle.panel(Color("120c08"), MenuUi.GOLD_DARK, 1, 6))
	say.text_submitted.connect(func(t: String) -> void:
		NetPlay.node().say(t)
		say.clear())
	cbox.add_child(say)

	var out := _back(s, "create", "ออกจากห้อง")
	out.pressed.disconnect(out.pressed.get_connections()[0]["callable"])
	out.pressed.connect(_leave_lobby)
	_ready_btn = MenuUi.small_button("", "", 150)
	_ready_btn.custom_minimum_size.y = 52
	_ready_btn.position = Vector2(W - 382, 480)
	_ready_btn.add_theme_font_size_override("font_size", 17)
	_ready_btn.pressed.connect(func() -> void:
		sfx.play("select")
		NetPlay.node().set_ready(NetPlay.node().my_seat, not _my_lobby_seat().get("ready", false)))
	s.add_child(_ready_btn)
	_start_btn = MenuUi.big_button("swords", "เริ่มเกม", "START GAME", true, 200)
	_start_btn.position = Vector2(W - 220, 480)
	_start_btn.custom_minimum_size.y = 52
	_start_btn.pressed.connect(_start_game)
	s.add_child(_start_btn)
	return s


func _enter_lobby() -> void:
	_countdown = -1.0
	_starting = false
	_chat_log.clear()
	if NetPlay.node().seats.is_empty():
		NetPlay.node().open_lobby(_my_char())
	if NetPlay.node().is_guest():
		_chat("[color=#b9a98a]คุณเข้าห้อง \"%s\" · รอหัวห้องเริ่มเกม[/color]" % GameConfig.room_name)
	else:
		_chat("[color=#b9a98a]คุณสร้างห้อง \"%s\" (หัวห้อง) · %s[/color]" % [GameConfig.room_name,
			GameConfig.PRESETS[GameConfig.preset]["name"]])
		if NetPlay.node().is_host():
			_chat("[color=#ffd76a]เลขห้อง %s · ส่งให้เพื่อนกด \"ใส่เลขห้อง\" เพื่อเข้ามาเล่นด้วย[/color]" % NetPlay.node().code)
			_chat("[color=#b9a98a]ที่ว่างที่ไม่มีคนเข้า บอทจะเล่นแทน[/color]")
			_chat("[color=#e0a070]หัวห้องเป็นคนเดินเกม: อย่าสลับแท็บหรือปิดหน้านี้ระหว่างเล่น (เกมจะหยุดสำหรับทุกคน)[/color]")
	_render_lobby()


## The character you had last (or the first one).
func _my_char() -> String:
	if not GameConfig.characters.is_empty() and CharacterDB.ids().has(GameConfig.characters[0]):
		return GameConfig.characters[0]
	return CharacterDB.ids()[0]


func _my_lobby_seat() -> Dictionary:
	return NetPlay.node().seats[NetPlay.node().my_seat] if NetPlay.node().my_seat < NetPlay.node().seats.size() else {}


## Redraw the lobby from NetPlay.node().seats: the line-up, the player list, Ready and Start.
func _render_lobby() -> void:
	if NetPlay.node().seats.is_empty() or not _screens["lobby"].visible:
		return
	_lobby_title.text = GameConfig.room_name + ("   ·   #%s" % NetPlay.node().code if NetPlay.node().online() else "")
	var me := _my_lobby_seat()
	if me.is_empty():
		return
	_pick_buttons[me["char"]].button_pressed = true
	var c := CharacterDB.get_character(me["char"])
	_pick_info.text = "อาวุธ: %s  ·  ท่าโจมตี: %s  ·  ท่าสังหาร: %s" % [c["weapon"], c["attack"], c["finisher"]]
	for child in _lineup.get_children():
		child.queue_free()
	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()
	var n := NetPlay.node().seats.size()
	var slot_w := minf(180.0, (590.0 - (n - 1) * 10.0) / n)
	for i in n:
		_lineup.add_child(_seat_slot(i, slot_w))
		_players_box.add_child(_player_row(i))
	_players_head.text = "ผู้เล่น %d คน · บอท %d" % [NetPlay.node().seats.filter(func(s: Dictionary) -> bool: return s["human"]).size(),
		NetPlay.node().seats.filter(func(s: Dictionary) -> bool: return not s["human"]).size()]
	_ready_btn.text = "ยกเลิกพร้อม" if me["ready"] else "พร้อม"
	var all := NetPlay.node().all_ready()
	_start_btn.visible = not NetPlay.node().is_guest()
	_ready_btn.position.x = W - 20 - 150 if NetPlay.node().is_guest() else W - 382  # alone at the edge for guests
	if NetPlay.node().is_guest():
		pass
	elif GameConfig.start_mode == "auto":
		_start_btn.disabled = true
		if all and _countdown < 0.0:
			_countdown = AUTO_START_SECONDS
			_chat("[color=#ffd76a]ทุกคนพร้อม · เริ่มใน %d วินาที[/color]" % int(AUTO_START_SECONDS))
		elif not all and _countdown >= 0.0:
			_countdown = -1.0
			_chat("[color=#e0a070]ยกเลิกการนับถอยหลัง[/color]")
	else:
		_start_btn.disabled = not all
	_start_label()


func _start_label() -> void:
	var main: Label = _start_btn.get_child(0).get_child(-1).get_child(0)
	var sub: Label = _start_btn.get_child(0).get_child(-1).get_child(1)
	if GameConfig.start_mode == "auto":
		main.text = "เริ่มใน %d" % ceili(_countdown) if _countdown >= 0.0 else "เริ่มอัตโนมัติ"
		sub.text = "รอทุกคนพร้อม" if _countdown < 0.0 else ""
	else:
		main.text = "เริ่มเกม"
		sub.text = "" if NetPlay.node().all_ready() else "รอทุกคนกดพร้อม"
	sub.visible = sub.text != ""


func _process(delta: float) -> void:
	_find_refresh -= delta
	if _screens.has("find") and _screens["find"].visible and _find_refresh <= 0.0:
		_find_refresh = FIND_REFRESH_SECONDS
		NetPlay.node().list_rooms()
	if _countdown < 0.0 or _starting:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		_countdown = -1.0
		_start_game()
	else:
		_start_label()


## You chose `id` (it takes your Ready back).
func _pick(id: String) -> void:
	sfx.play("select")
	NetPlay.node().pick(id)


func _seat_slot(i: int, w: float) -> Control:
	var s: Dictionary = NetPlay.node().seats[i]
	var me := i == NetPlay.node().my_seat
	var c := CharacterDB.get_character(s["char"])
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(w, 0)
	box.add_theme_constant_override("separation", 2)
	box.add_child(CharacterPreview.new(c["id"], Vector2(w, 200), me))
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiStyle.panel(Color("1d3a5c") if me else Color("2b1d12"),
		MenuUi.GOLD if me else MenuUi.GOLD_DARK, 2 if me else 1, 6))
	box.add_child(plate)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", -2)
	plate.add_child(inner)
	var who := MenuUi.label(("★ " if me else "") + s["name"], 15, MenuUi.GOLD if me else UiStyle.TEXT)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.clip_text = true
	inner.add_child(who)
	var what := MenuUi.label(c["name"] + ("" if s["human"] else " · บอท"), 11, UiStyle.TEXT_DIM)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	what.clip_text = true  # 6 seats: narrow plates
	inner.add_child(what)
	return box


func _player_row(i: int) -> Control:
	var s: Dictionary = NetPlay.node().seats[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var c := CharacterDB.get_character(s["char"])
	row.add_child(Icons.rect(c["icon"], 22))
	var name := MenuUi.label(s["name"], 14, MenuUi.GOLD if i == NetPlay.node().my_seat else UiStyle.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	row.add_child(name)
	var role := "หัวห้อง" if i == 0 else ("ผู้เล่น" if s["human"] else "บอท")
	var tag := MenuUi.label("%s · %s" % [role, "พร้อม" if s["ready"] else "รอ..."], 12)
	tag.add_theme_color_override("font_color", Color("7fc97f") if s["ready"] else UiStyle.TEXT_DIM)
	row.add_child(tag)
	return row


func _chat(bbcode: String) -> void:
	_chat_log.append_text(bbcode + "\n")


func _leave_lobby() -> void:
	var was_guest := NetPlay.node().is_guest()
	NetPlay.node().leave()
	NetPlay.node().seats.clear()
	show_screen("home" if was_guest else "create")


func _start_game() -> void:
	if _starting or NetPlay.node().is_guest():
		return
	_starting = true
	sfx.play("confirm")
	NetPlay.node().start()
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.45)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(TABLE_SCENE))


# ---------- badge, toast, settings, how to play ----------

func _build_badge() -> void:
	var b := Button.new()
	b.position = Vector2(W - 20 - 46 - 8 - 190, 12)  # left of the full screen button
	b.custom_minimum_size = Vector2(190, 46)
	b.add_theme_stylebox_override("normal", MenuUi.panel_style(MenuUi.GOLD_DARK, 2, MenuUi.PANEL))
	b.add_theme_stylebox_override("hover", MenuUi.panel_style(MenuUi.GOLD, 2, MenuUi.PANEL))
	b.add_theme_stylebox_override("pressed", MenuUi.panel_style(MenuUi.GOLD, 2, MenuUi.PANEL))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.tooltip_text = "ตั้งค่าชื่อผู้เล่น"
	b.pressed.connect(_open_settings)
	add_child(b)
	var full := ScreenMode.button(46)  # full screen, in the corner beside the badge and as tall
	full.position = Vector2(W - 20 - 46, 12)
	full.add_theme_stylebox_override("normal", MenuUi.panel_style(MenuUi.GOLD_DARK, 2, MenuUi.PANEL))
	full.add_theme_stylebox_override("hover", MenuUi.panel_style(MenuUi.GOLD, 2, MenuUi.PANEL))
	full.add_theme_stylebox_override("pressed", MenuUi.panel_style(MenuUi.GOLD, 2, MenuUi.PANEL))
	add_child(full)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var star := Icons.rect("star", 26)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(star)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -3)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	_badge_name = MenuUi.label(GameConfig.player_name, 15, MenuUi.GOLD)
	_badge_name.clip_text = true
	texts.add_child(_badge_name)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", MenuUi.panel_style(MenuUi.GOLD, 2))
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast_label = MenuUi.label("", 15)
	_toast.add_child(_toast_label)
	_toast.resized.connect(func() -> void: _toast.position = Vector2((W - _toast.size.x) / 2, 420))


func toast(text: String) -> void:
	_toast_label.text = text
	_toast.size = Vector2.ZERO
	_toast.visible = true
	_toast.modulate.a = 1.0
	var t := _toast.create_tween()
	t.tween_interval(2.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void: _toast.visible = false)


## A box over a dark veil; returns the box to fill. Closing frees it.
func _open_modal(title: String, box_size: Vector2) -> VBoxContainer:
	if _modal:
		_modal.queue_free()
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.6)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(veil)
	var p := MenuUi.panel((Vector2(W, 540) - box_size) / 2, box_size, MenuUi.GOLD)
	_modal.add_child(p)
	p.resized.connect(func() -> void: p.position = (Vector2(W, 540) - p.size) / 2)  # its contents can widen it
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	var head := MenuUi.label("◆  " + title + "  ◆", 20, MenuUi.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	return box


func _close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func _open_settings() -> void:
	var box := _open_modal("ตั้งค่า", Vector2(440, 270))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 16)
	box.add_child(grid)
	var name := LineEdit.new()
	name.text = GameConfig.player_name
	name.max_length = GameConfig.NAME_MAX
	MenuUi.keyboard_limit(name)
	name.custom_minimum_size = Vector2(260, 34)
	name.add_theme_stylebox_override("normal", UiStyle.panel(Color("120c08"), MenuUi.GOLD_DARK, 1, 6))
	_form_row(grid, "ชื่อผู้เล่น", name)
	var vol_row := HBoxContainer.new()
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.value = roundf(GameConfig.sfx_volume * 100)
	vol.custom_minimum_size = Vector2(200, 30)
	vol_row.add_child(vol)
	var vol_label := MenuUi.label("%d%%" % vol.value, 14)
	vol_row.add_child(vol_label)
	vol.value_changed.connect(func(v: float) -> void:
		vol_label.text = "%d%%" % v
		GameConfig.sfx_volume = v / 100.0
		GameConfig.apply_volume())
	vol.drag_ended.connect(func(_changed: bool) -> void: sfx.play("select"))
	_form_row(grid, "ระดับเสียง", vol_row)
	box.add_child(Control.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var old_volume := GameConfig.sfx_volume
	var save := MenuUi.small_button("  บันทึก  ", "", 120)
	save.pressed.connect(func() -> void:
		var n := name.text.strip_edges()
		GameConfig.player_name = n if n != "" else "ผู้เล่น"
		GameConfig.save_settings()
		_badge_name.text = GameConfig.player_name
		if GameConfig.names.size() > 0:
			GameConfig.names[0] = GameConfig.player_name
		if _screens["lobby"].visible:
			NetPlay.node().rename(GameConfig.player_name)
		_close_modal()
		toast("บันทึกการตั้งค่าแล้ว"))
	row.add_child(save)
	var cancel := MenuUi.small_button("  ยกเลิก  ", "", 120)
	cancel.pressed.connect(func() -> void:
		GameConfig.sfx_volume = old_volume
		GameConfig.apply_volume()
		_close_modal())
	row.add_child(cancel)


## How to Play: real screenshots from the game (assets/howto, made with tests/shot_shop.gd
## and tests/shot_seats.gd), one step per page with a short caption.
const HOWTO := [
	["01_opening", "เริ่มเกม", "ทุกคนทอยเต๋า 3 ลูก แต้มมากสุดได้เล่นก่อน
ป้ายผู้เล่นด้านบนจะเรียงตามลำดับการเล่น"],
	["02_noshop", "ป้ายผู้เล่น", "ป้ายใหญ่หน้าสุดคือคนที่กำลังเล่น ป้ายเล็กถัดไปเรียงตามคิว และเลื่อนไปทุกเทิร์น
บอกเลือด แหวน จำนวนการ์ด และสถานะ ป้ายสีฟ้าที่มีดาวคือป้ายของคุณ"],
	["03_roll", "ทอยเต๋า", "ตาของคุณเริ่มด้วยการกด \"ทอยลูกเต๋า\"
ได้เงิน = ผลรวม ÷ 2 และจั่วการ์ดเพิ่ม 2 ใบ"],
	["04_shop", "ร้านค้า", "ช่วงเตรียมตัว กด \"ร้านค้า\" เพื่อซื้อการ์ด
เศษแหวน 2 ชิ้น แลกเป็นแหวนได้ 1 วง"],
	["05_target", "โจมตี", "ช่วงต่อสู้ กดการ์ดโจมตี แล้วคลิกตัวละครที่เรืองแสงสีส้ม
โดนแล้วเสียเลือด 1 หมดเลือด = ตกรอบ พร้อมท่าไม้ตายของตัวละครที่โจมตี"],
	["06_defend", "ป้องกัน", "เมื่อมีคนโจมตีคุณ จะถามว่าใช้การ์ดป้องกันไหม
กด \"ป้องกัน\" แล้วไม่เสียเลือด"],
	["07_self", "การ์ดช่วยเหลือและคำสาป", "การ์ดเขียวช่วยตัวเอง (ฟื้นเลือด ล้างคำสาป) การ์ดม่วงสาปคนอื่น (ห้ามซื้อ ตาบอด ...)
ไอคอนบนหัวตัวละครและบนป้ายบอกว่าใครโดนอะไรอยู่"],
	["08_minigame", "มินิเกม", "ทุก 2 รอบ ทายของที่อยู่ในอันดับ 1–100 พิมพ์คำตอบภายใน 15 วินาที
ได้คะแนนมาก = ได้เศษแหวนและเงินมาก"],
	["09_shrink", "เลือดและการ์ดสูงสุดลดลง", "ทุก 5 รอบ เลือดสูงสุดและการ์ดในมือสูงสุดของทุกคนลดลง 1 (ตัวเลขใต้ป้ายรอบคือจำนวนรอบที่เหลือ)
ช่องเลือดที่ถูกตัดออกจะเป็นสีดำ"],
	["10_result", "ชนะ!", "สะสมแหวนครบตามที่ตั้งห้องไว้ หรือเป็นคนสุดท้ายที่รอด
จบเกมแล้วดูอันดับ คะแนน และเล่นต่อได้ทันที"],
]


func _open_howto(page := 0) -> void:
	var box := _open_modal("วิธีเล่น  ·  %d / %d" % [page + 1, HOWTO.size()], Vector2(800, 524))
	box.add_theme_constant_override("separation", 4)
	var step: Array = HOWTO[page]
	var frame := PanelContainer.new()
	var fs := UiStyle.panel(Color.BLACK, MenuUi.GOLD_DARK, 2, 6)
	fs.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", fs)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(frame)
	var pic := TextureRect.new()
	pic.texture = load("res://assets/howto/%s.png" % step[0])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(560, 315)
	pic.mouse_filter = Control.MOUSE_FILTER_STOP
	pic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pic.gui_input.connect(func(e: InputEvent) -> void:  # click the picture for the next step
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_howto((page + 1) % HOWTO.size()))
	frame.add_child(pic)
	var head := MenuUi.label("%d. %s" % [page + 1, step[1]], 18, MenuUi.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var caption := MenuUi.label(step[2], 13, UiStyle.TEXT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_constant_override("line_spacing", -8)  # the Thai font's lines are tall
	box.add_child(caption)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 14)
	box.add_child(nav)
	var prev := MenuUi.small_button("  ◀  ก่อนหน้า  ", "", 130)
	prev.disabled = page == 0
	prev.pressed.connect(_open_howto.bind(page - 1))
	nav.add_child(prev)
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 6)
	nav.add_child(dots)
	for i in HOWTO.size():  # page dots: click one to jump there
		var d := Button.new()
		d.custom_minimum_size = Vector2(12, 12)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for state: String in ["normal", "hover", "pressed"]:
			var ds := UiStyle.panel(Color("ffe08a") if state == "hover" else (MenuUi.GOLD if i == page else Color("4a3a28")),
				MenuUi.GOLD_DARK, 1, 6)
			ds.set_content_margin_all(0)
			d.add_theme_stylebox_override(state, ds)
		d.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		d.pressed.connect(_open_howto.bind(i))
		dots.add_child(d)
	var last := page == HOWTO.size() - 1
	var next := MenuUi.small_button("  ปิด  " if last else "  ถัดไป  ▶  ", "", 130)
	next.pressed.connect(_close_modal if last else _open_howto.bind(page + 1))
	nav.add_child(next)
	var close := MenuUi.small_button("✕", "", 34)  # top-right corner of the box
	close.position = (Vector2(W, 540) - Vector2(800, 524)) / 2 + Vector2(800 - 46, 10)
	close.pressed.connect(_close_modal)
	_modal.add_child(close)
