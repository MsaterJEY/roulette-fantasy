class_name MinigamePanel
extends Control
## The "guess the rank" window over the felt: question, scores, answers so far, whose turn
## and the time left. On your turn you type an answer (Enter or "ตอบ") or pass.
## When it ends it shows the places and rewards until the game goes on.

var game: GameController
var _title: Label
var _question: Label
var _scores: HFlowContainer
var _answers: RichTextLabel
var _turn: Label
var _input_row: HBoxContainer
var _input: LineEdit
var _error: Label
var _results: Array[Dictionary] = []

const INK := Color("3b2412")  # writing on the parchment
const INK_SOFT := Color("6e4f2e")


func setup(p_game: GameController) -> void:
	game = p_game
	game.minigame_started.connect(_on_started)
	game.minigame_changed.connect(_refresh)
	game.minigame_finished.connect(func(results: Array[Dictionary]) -> void:
		_results = results
		_refresh())


func _ready() -> void:
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(60, 24)
	panel.size = Vector2(size.x - 120, size.y - 48)
	var sheet := StyleBoxTexture.new()  # an old map; tools/make_parchment.py
	sheet.texture = load("res://assets/ui/parchment.png")
	sheet.content_margin_left = 30
	sheet.content_margin_right = 30
	sheet.content_margin_top = 34
	sheet.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sheet)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	# the title on a wooden plate across the top edge
	var plate := PanelContainer.new()
	var plate_style := UiStyle.panel(Color("3a2312"), UiStyle.BRASS, 2, 6)
	plate_style.content_margin_left = 26
	plate_style.content_margin_right = 26
	plate_style.content_margin_top = 3
	plate_style.content_margin_bottom = 3
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	plate.resized.connect(func() -> void:
		plate.position = Vector2(size.x / 2 - plate.size.x / 2, panel.position.y - 9))
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", UiStyle.ACTIVE)
	plate.add_child(_title)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var compass := TextureRect.new()
	compass.texture = load("res://assets/ui/compass.png")
	compass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	compass.custom_minimum_size = Vector2(54, 54)
	compass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(compass)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(words)
	_question = _label(words, 22, INK)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _label(words, 12, INK_SOFT)
	hint.text = "คะแนน = 101 − อันดับ · ไม่อยู่ในรายการ = 0 · ห้ามตอบซ้ำกับที่มีคนตอบแล้ว"

	# the answer box stays high up: a phone's keyboard covers the lower half of the screen
	var turn_plate := PanelContainer.new()
	var turn_style := UiStyle.panel(Color("4a2c14"), UiStyle.BRASS.darkened(0.2), 1, 13)
	turn_style.content_margin_left = 16
	turn_style.content_margin_right = 16
	turn_style.content_margin_top = 1
	turn_style.content_margin_bottom = 1
	turn_plate.add_theme_stylebox_override("panel", turn_style)
	turn_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(turn_plate)
	_turn = Label.new()
	_turn.add_theme_font_size_override("font_size", 14)
	turn_plate.add_child(_turn)
	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 8)
	box.add_child(_input_row)
	_input = LineEdit.new()
	MenuUi.keyboard_limit(_input)
	_input.placeholder_text = "พิมพ์คำตอบ (ไทยหรืออังกฤษ)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size.y = 36
	var field := UiStyle.panel(Color("f6ead0"), Color("a97c2f"), 2, 6)
	field.content_margin_left = 10
	field.content_margin_right = 10
	_input.add_theme_stylebox_override("normal", field)
	_input.add_theme_stylebox_override("focus", UiStyle.panel(Color(0, 0, 0, 0), Color("7a2e12"), 2, 6))
	_input.add_theme_color_override("font_color", INK)
	_input.add_theme_color_override("caret_color", INK)
	_input.add_theme_color_override("font_placeholder_color", INK_SOFT)
	_input.text_submitted.connect(func(_t: String) -> void: _send(_input.text))
	_input_row.add_child(_input)
	var send := _map_button("ตอบ", Color("8c2a1c"), 76)
	send.pressed.connect(func() -> void: _send(_input.text))
	_input_row.add_child(send)
	var skip := _map_button("ข้าม", Color("5c3a1c"), 66)
	skip.pressed.connect(func() -> void: _send(""))
	_input_row.add_child(skip)
	_error = _label(box, 12, Color("9c1f12"))
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 8)
	box.add_child(score_row)
	var star := Icons.rect("star", 20)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_row.add_child(star)
	_scores = HFlowContainer.new()  # wraps onto a second line with 5-6 players
	_scores.add_theme_constant_override("h_separation", 16)
	_scores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(_scores)

	var log_box := PanelContainer.new()
	var log_style := UiStyle.panel(Color(0.42, 0.25, 0.1, 0.13), Color(0.36, 0.22, 0.1, 0.45), 1, 6)
	log_style.set_content_margin_all(6)
	log_box.add_theme_stylebox_override("panel", log_style)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(log_box)
	_answers = RichTextLabel.new()
	_answers.bbcode_enabled = true
	_answers.scroll_following = true
	_answers.add_theme_font_size_override("normal_font_size", 13)
	_answers.add_theme_font_size_override("bold_font_size", 13)
	_answers.add_theme_color_override("default_color", INK)
	log_box.add_child(_answers)
	if PhoneField.wanted():
		add_child(PhoneField.new(_input))


func _map_button(text: String, color: Color, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 0)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color("fff0cc"))
	b.add_theme_color_override("font_hover_color", Color("fff0cc"))
	b.add_theme_color_override("font_pressed_color", Color("fff0cc"))
	b.add_theme_stylebox_override("normal", UiStyle.panel(color, UiStyle.BRASS, 2, 6))
	b.add_theme_stylebox_override("hover", UiStyle.panel(color.lightened(0.12), UiStyle.ACTIVE, 2, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.panel(color.darkened(0.2), UiStyle.BRASS, 2, 6))
	return b


func _label(parent: Container, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _on_started() -> void:
	_results = []
	_error.text = ""
	_input.text = ""
	_refresh()


func _send(text: String) -> void:
	var reason := game.minigame_answer(game.players[0], text)
	_error.text = reason
	if reason == "":
		_input.text = ""


func _refresh() -> void:
	var mg := game.minigame
	visible = mg != null
	if mg == null:
		return
	_title.text = "Minigame · ทายอันดับ   รอบ %d/%d" % [mini(mg.round_no, Minigame.ROUNDS), Minigame.ROUNDS]
	_question.text = mg.question["question"]
	for child in _scores.get_children():
		child.queue_free()
	for s in mg.seats:
		var l := Label.new()
		l.text = "%s %d" % [game.players[s].display_name, mg.scores[s]]
		var on_turn := not mg.done() and s == mg.current_seat()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color("9c1f12") if on_turn else INK)
		_scores.add_child(l)
	_answers.clear()
	for a in mg.answers:
		var who: String = game.players[a["seat"]].display_name
		var what: String
		if a["text"] == "":
			what = "[color=#6e4f2e]ไม่ตอบ[/color]"
		elif a["rank"] == 0:
			what = "%s [color=#6e4f2e](ไม่อยู่ในรายการ +0)[/color]" % a["text"]
		else:
			what = "[b]%s[/b] [color=#8a4a00]อันดับ %d · +%d[/color]" % [a["text"], a["rank"], a["points"]]
		_answers.append_text("รอบ %d · %s: %s\n" % [a["round"], who, what])
	if mg.done():
		_answers.append_text("\n[color=#8c2a1c][b]ผลมินิเกม[/b][/color]\n")
		for r in _results:
			_answers.append_text("ที่ %d  %s  %d แต้ม  →  เศษแหวน +%d  เงิน +%d\n" % [
				r["place"], game.players[r["seat"]].display_name, r["score"], r["shards"], r["gold"]])
	var mine := not mg.done() and game.is_me(game.players[mg.current_seat()])
	_input_row.visible = mine
	if mine and _input.focus_mode != Control.FOCUS_NONE:
		_input.grab_focus.call_deferred()
	else:
		_error.text = ""
		_input.text = ""  # an answer not sent in time doesn't carry over


func _process(_delta: float) -> void:
	var mg := game.minigame if game else null
	if mg == null or not visible:
		return
	if mg.done():
		_turn.text = "จบมินิเกม · เกมจะเล่นต่อในไม่ช้า"
		return
	var p := game.players[mg.current_seat()]
	var who := "ตาของคุณ!" if game.is_me(p) else "ตาของ %s" % p.display_name
	_turn.text = "%s   เหลือ %.1f วินาที" % [who, maxf(mg.time_left, 0.0)]
	_turn.add_theme_color_override("font_color", Color("ff5a4f") if mg.time_left <= 5.0 else UiStyle.ACTIVE)
