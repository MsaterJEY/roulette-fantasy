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
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.WOOD_DARK, UiStyle.BRASS, 3, 10))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_title = _label(box, 14, UiStyle.BRASS)
	_question = _label(box, 22, UiStyle.ACTIVE)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _label(box, 12, UiStyle.TEXT_DIM)
	hint.text = "คะแนน = 101 − อันดับ · ไม่อยู่ในรายการ = 0 · ห้ามตอบซ้ำกับที่มีคนตอบแล้ว"
	_scores = HFlowContainer.new()  # wraps onto a second line with 5-6 players
	_scores.add_theme_constant_override("h_separation", 16)
	box.add_child(_scores)

	_answers = RichTextLabel.new()
	_answers.bbcode_enabled = true
	_answers.scroll_following = true
	_answers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_answers.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_answers)

	_turn = _label(box, 15, UiStyle.TEXT)
	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 8)
	box.add_child(_input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "พิมพ์คำตอบ (ไทยหรืออังกฤษ)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t: String) -> void: _send(_input.text))
	_input_row.add_child(_input)
	var send := Button.new()
	send.text = "ตอบ"
	send.custom_minimum_size = Vector2(70, 0)
	send.pressed.connect(func() -> void: _send(_input.text))
	_input_row.add_child(send)
	var skip := Button.new()
	skip.text = "ข้าม"
	skip.custom_minimum_size = Vector2(60, 0)
	skip.pressed.connect(func() -> void: _send(""))
	_input_row.add_child(skip)
	_error = _label(box, 12, Color("ff6b6b"))


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
		l.add_theme_color_override("font_color", UiStyle.ACTIVE if on_turn else UiStyle.TEXT)
		_scores.add_child(l)
	_answers.clear()
	for a in mg.answers:
		var who: String = game.players[a["seat"]].display_name
		var what: String
		if a["text"] == "":
			what = "[color=#b9a98a]ไม่ตอบ[/color]"
		elif a["rank"] == 0:
			what = "%s [color=#b9a98a](ไม่อยู่ในรายการ +0)[/color]" % a["text"]
		else:
			what = "[b]%s[/b] [color=#f0c419]อันดับ %d · +%d[/color]" % [a["text"], a["rank"], a["points"]]
		_answers.append_text("รอบ %d · %s: %s\n" % [a["round"], who, what])
	if mg.done():
		_answers.append_text("\n[color=#ffd76a][b]ผลมินิเกม[/b][/color]\n")
		for r in _results:
			_answers.append_text("ที่ %d  %s  %d แต้ม  →  เศษแหวน +%d  เงิน +%d\n" % [
				r["place"], game.players[r["seat"]].display_name, r["score"], r["shards"], r["gold"]])
	var mine := not mg.done() and game.is_human(game.players[mg.current_seat()])
	_input_row.visible = mine
	if mine:
		_input.grab_focus.call_deferred()
	else:
		_error.text = ""


func _process(_delta: float) -> void:
	var mg := game.minigame if game else null
	if mg == null or not visible:
		return
	if mg.done():
		_turn.text = "จบมินิเกม · เกมจะเล่นต่อในไม่ช้า"
		return
	var p := game.players[mg.current_seat()]
	var who := "ตาของคุณ!" if game.is_human(p) else "ตาของ %s" % p.display_name
	_turn.text = "%s   เหลือ %.1f วินาที" % [who, maxf(mg.time_left, 0.0)]
	_turn.add_theme_color_override("font_color", Color("ff5a4f") if mg.time_left <= 5.0 else UiStyle.ACTIVE)
