extends Control
## The game screen: a first-person 3D tavern (TavernView) behind a 2D HUD. All four players'
## cards sit in a bar along the top (bots A-C, then you) with the round/phase plate under
## it; the game history is top-right; gold bottom-left, your hand bottom-centre, the Shop
## and Next buttons bottom-right. Built in code; the rules live in GameController and this
## script only shows them and forwards your clicks. The game starts after you pick your
## character (CharacterSelect); the bots get the others, named after their character.

## Set before the table enters the tree to skip the lobby's choice (tests): the character
## id to play, or "random".
var auto_pick := ""
# places in the top bar, left to right, centred for 2-4 players; the player cards sit in
# turn order (set by the opening dice roll), before that in seat order (you first)
const SLOT_SIZE := Vector2(146, 58)
const SLOT_STEP := 150.0
## 5-6 players: narrower cards (no portrait) so the bar still fits the screen.
const SLOT_SIZE_COMPACT := Vector2(128, 58)
const SLOT_STEP_COMPACT := 132.0
const BAR_CENTRE := 480.0  # the middle of the screen
const MARGIN := 16.0  # the gap at the left and right edges of the screen
var _seat_count := 4

var game: GameController
var seats: Array[SeatPanel] = []
var tavern: TavernView
## Effects on you, round the screen edges: `status_fx` stays while blind/truce, `hit_fx` flashes.
var status_fx: Vignette
var hit_fx: Vignette
var hand_lock: Control  # "no items" badge over your hand
var hand_hint: Label  # why the card you clicked can't be played, over your hand for a moment
var _hint_tween: Tween
var self_target_button: Button  # "use on yourself" while aiming a card that may target you
var round_label: Label
var phase_label: Label
var showdown_label: Label  # rounds left until max HP and the hand limit drop
var showdown_plate: PanelContainer  # dark plate under it
var dice_tip: PanelContainer  # how a roll turns into gold (the dice button top right)
var _dice_tip_pinned := false
## Time left, drawn round the frame of the seat that has to act.
var turn_bar: TurnTimerBar
## The same time as digits (seconds.milliseconds), left of your seat.
var time_label: Label
var action_button: Button
var hand_box: Control
var sfx: Sfx  # the sound effects the user picked in the sound lab
var log_box: RichTextLabel
var log_panel: PanelContainer
var log_tab: Button  # the folded history: a tab on the right edge
var defense_panel: PanelContainer
var defense_label: Label
var banner: Label
var turn_toast: Label
var roll_panel: PanelContainer
var roll_title: Label
var roll_dice: Array[DiceView] = []
var roll_gold: Label
var roll_cards: Label
var _roll_tween: Tween
var gold_panel: PanelContainer
var gold_label: Label
var _shown_gold := -1
var shop_button: Button
var shop_panel: PanelContainer
var shop_list: VBoxContainer
var minigame_panel: MinigamePanel
var result_panel: ResultPanel
var _targeting: Dictionary = {}  # {"index": hand index, "card": card} while choosing a target
var _hand_map: Array[int] = []  # button order -> hand index (shuffled while blind)
var _replacing := -1  # shop slot being bought with a full hand: click a hand card to swap it out
var _order_badges: Array[PanelContainer] = []  # opening roll result under each player card
var _card_lands_ms := 0  # when the card in flight arrives: hit/block effects wait for it
var _ko_until_ms: Dictionary = {}  # seat -> when its finisher ends (the knockout pose waits)
var _dying_cards: Dictionary = {}  # seat -> cards in hand when the killing blow landed
var move_label: Label  # the attack's move name, flashed at the top of the table
var _select: CharacterSelect


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game = GameController.new()
	if DisplayServer.get_name() == "headless" and not NetPlay.node().online():
		# smoke tests: bots play every seat, fast
		game.autoplay = true
		game.speed = 8.0
	add_child(game)
	sfx = Sfx.new()
	add_child(sfx)
	game.log_added.connect(add_log)
	game.rolled.connect(_on_rolled)
	game.attack_incoming.connect(_on_attack_incoming)
	game.game_over.connect(_on_game_over)
	game.attacked.connect(_on_attacked)
	game.showdown_shrunk.connect(_on_showdown_shrunk)
	game.card_played.connect(_on_card_played)

	GameConfig.load_settings()
	_seat_count = clampi(GameConfig.players, 2, 6)
	SeatPanel.compact = _seat_count > 4
	_build_table()
	_build_hand()
	_build_log()
	if auto_pick == "" and game.autoplay:
		auto_pick = "random"
	if auto_pick != "":
		_start(CharacterDB.ids().pick_random() if auto_pick == "random" else auto_pick)
	elif NetPlay.node().is_guest():  # online: the host's game arrives, then the table is set up from it
		NetPlay.node().attach_guest(game, _start.bind(GameConfig.characters[0]))
	elif NetPlay.node().is_host():  # online: everyone's table is open before the game starts
		NetPlay.node().attach_host(game)
		NetPlay.node().when_guests_ready(_start.bind(GameConfig.characters[0]))
	elif GameConfig.characters.size() == _seat_count:
		_start(GameConfig.characters[0])  # seated in the lobby
	else:
		_select = CharacterSelect.new()
		_select.sfx = sfx
		_select.size = Vector2(960, 540)
		add_child(_select)
		_select.chosen.connect(_start)


## You picked `my_id`: the bots take the other characters in random seats, and the game
## begins (with the opening roll-off).
func _start(my_id: String) -> void:
	if _select:
		_select.queue_free()
		_select = null
	if GameConfig.characters.size() != _seat_count or GameConfig.characters[0] != my_id:
		GameConfig.players = _seat_count
		GameConfig.fill_seats(my_id)  # no lobby (tests, or the table run on its own)
		GameConfig.humans.clear()
	var ids: Array = GameConfig.characters.duplicate()
	var names: Array = GameConfig.names.duplicate()
	game.rings_to_win = GameConfig.rings_to_win
	game.minigames_enabled = GameConfig.minigames
	game.step_seconds = GameConfig.turn_seconds
	SeatPanel.rings_max = GameConfig.rings_to_win
	SeatPanel.hp_max = game.max_hp  # static: back to full after last game's shrinking
	if not game.is_mirror():  # a guest's game is already the host's
		game.start_game(names, ids, GameConfig.humans)
	if NetPlay.node().is_host():
		NetPlay.node().send_init()
	tavern.sfx = sfx
	tavern.setup_characters(ids)
	game.bought.connect(func(seat: int, _card: Dictionary) -> void:
		if seat == 0:
			sfx.play("coin"))
	for i in game.players.size():
		seats[i].setup(game.players[i])
		seats[i].clicked.connect(_on_seat_clicked)
	_build_defense_panel()
	_build_shop()
	_build_banner()
	_build_move_label()
	_build_turn_toast()
	_build_roll_panel()
	_build_gold_counter()
	_build_dice_tip()
	_build_minigame_and_result()
	# connected after the UI exists; the first turn starts once the opening roll-off is shown
	game.turn_started.connect(_on_turn_started)
	game.state_changed.connect(refresh_all)
	_show_opening(game.opening_rolls)
	refresh_all()


## The opening roll-off: each player throws the 3D dice in turn and their total appears
## under their card; then the cards slide into turn order (highest total first).
func _show_opening(rolls: Array[Dictionary]) -> void:
	var step := GameController.OPENING_THROW_SECONDS / game.speed
	var t := create_tween()
	t.tween_interval(GameController.OPENING_WAIT_SECONDS / game.speed)  # a moment before the first throw
	for r in rolls:
		var seat: int = r["seat"]
		var badge := _order_badge(seat)
		t.tween_callback(func() -> void:
			tavern.throw_dice(seat, r["dice"], GameController.ROLL_SECONDS / game.speed))
		t.tween_interval(GameController.ROLL_SECONDS / game.speed)
		t.tween_callback(func() -> void:
			var totals: Array = r["totals"]
			_set_badge(badge, " → ".join(totals.map(func(v: int) -> String: return str(v))), false)
			badge.visible = true)
		t.tween_interval(maxf(0.0, step - GameController.ROLL_SECONDS / game.speed))
	t.tween_callback(func() -> void:
		for r in rolls:
			var place := game.order.find(r["seat"]) + 1
			var totals: Array = r["totals"]
			_set_badge(_order_badges[r["seat"]], "ลำดับ %d · %d แต้ม" % [place, totals[0]], place == 1)
		_place_cards(true))
	t.tween_interval(GameController.OPENING_SHOW_SECONDS / game.speed + 1.5)
	t.tween_callback(func() -> void:
		for b in _order_badges:
			b.create_tween().tween_property(b, "modulate:a", 0.0, 0.5))


## The `i`-th place in the top bar (the bar is centred for the number of players).
func _slot_rect(i: int) -> Rect2:
	var size := SLOT_SIZE_COMPACT if SeatPanel.compact else SLOT_SIZE
	var step := SLOT_STEP_COMPACT if SeatPanel.compact else SLOT_STEP
	var left := BAR_CENTRE - (_seat_count * step) / 2.0 + (step - size.x) / 2.0
	return Rect2(Vector2(left + i * step, 10), size)


## Put every player card in its top-bar place: turn order once it is known.
func _place_cards(animated: bool) -> void:
	for seat in seats.size():
		var slot := game.order.find(seat)
		var to: Vector2 = _slot_rect(slot).position
		if animated:
			var t := seats[seat].create_tween()
			t.tween_property(seats[seat], "position", to, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_order_badges[seat].create_tween().tween_property(_order_badges[seat], "position:x", to.x + 20, 0.45)
		else:
			seats[seat].position = to


func _order_badge(seat: int) -> PanelContainer:
	while _order_badges.size() <= seat:
		var b := PanelContainer.new()
		b.add_theme_stylebox_override("panel", UiStyle.panel(Color(0.08, 0.06, 0.05, 0.9), UiStyle.BRASS, 1, 10))
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		row.add_child(Icons.rect("dice", 14))
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)
		b.position = _slot_rect(_order_badges.size()).position + Vector2(20, 20)  # over the card while shown
		b.z_index = 5
		b.visible = false
		add_child(b)
		_order_badges.append(b)
	return _order_badges[seat]


func _set_badge(badge: PanelContainer, text: String, first: bool) -> void:
	var label: Label = badge.get_child(0).get_child(1)
	label.text = text
	label.add_theme_color_override("font_color", UiStyle.ACTIVE if first else UiStyle.TEXT)


func _exit_tree() -> void:
	Icons.clear()
	PixelTex.clear()
	Character3D.clear()


## Before the opening throws: "เริ่มทอยใน 3 / 2 / 1" under the plate.
func _opening_countdown() -> void:
	var left := game.opening_wait_left()
	if left > 0.0:
		phase_label.text = "เริ่มทอยใน %d" % ceili(left)



func _process(_delta: float) -> void:
	if game.players.is_empty():
		return  # still on the character screen
	_update_showdown_label()
	if game.in_opening():
		_opening_countdown()
	if game.finished or game.minigame != null or game.in_opening():
		turn_bar.visible = false
		time_label.visible = false
		return
	# while you decide whether to defend, the bar runs round your seat instead
	var seat := game.current().seat
	var left := game.time_left
	var total := game.step_seconds
	if not game.pending_attack.is_empty():
		seat = game.pending_attack["target"]
		left = game.pending_attack["time"]
		total = GameController.DEFENSE_SECONDS
	var r := seats[seat].get_rect().grow(2)
	turn_bar.position = r.position
	turn_bar.size = r.size
	turn_bar.fraction = left / total
	turn_bar.warning = left <= 5.0
	turn_bar.visible = true
	time_label.visible = true
	time_label.text = "%06.3f" % maxf(left, 0.0)
	time_label.add_theme_color_override("font_color", Color("ff5a4f") if left <= 5.0 else UiStyle.ACTIVE)


func add_log(bbcode: String) -> void:
	var icon := _log_icon(bbcode)
	var img := "[img=14x14]res://assets/icons/%s.png[/img] " % icon if icon != "" else "[color=#8a7a60]•[/color] "
	log_box.append_text(img + bbcode + "\n")


## Which icon goes in front of a history line, picked from what the line says.
func _log_icon(text: String) -> String:
	for c in CardDB.all():
		if ("ใช้ [b]%s[/b]" % c["name"]) in text:
			return c["id"]
	for c in CharacterDB.all():  # characters' Attack cards go by their weapon's name
		if ("ใช้ [b]%s[/b]" % c["weapon"]) in text:
			return c["icon"]
	for pair: Array in [["เทิร์นของ", "turn"], ["ทอยได้", "dice"], ["ซื้อ", "shop"], ["กันการโจมตี", "defense"],
			["เสียเลือด", "attack"], ["ตกรอบ", "attack"], ["Minigame", "star"], ["ตอบ", "star"],
			["แหวน", "ring"], ["จั่ว", "cards"], ["ได้เงิน", "shard"]]:
		if pair[0] in text:
			return pair[1]
	return ""


func refresh_all() -> void:
	var cur := game.current()
	for s in seats:
		s.set_active(s.player == cur)
		var hold := maxf(0.0, (_ko_until_ms.get(s.player.seat, 0) - Time.get_ticks_msec()) / 1000.0)
		tavern.set_seat_state(s.player.seat, s.player == cur, s.player.alive, s.player.statuses, hold)
	# step names are "English · ไทย": the plate shows the Thai part
	round_label.text = "◆   รอบที่ %d · %s   ◆" % [game.round_no, game.step_name().get_slice(" · ", 1)]
	phase_label.text = "เทิร์นของคุณ" if cur.seat == 0 else "เทิร์นของ %s" % cur.display_name
	if game.in_opening():
		round_label.text = "◆   ทอยลูกเต๋าเรียงลำดับการเล่น   ◆"
		phase_label.text = "แต้มมากสุดได้เล่นก่อน"
		_opening_countdown()
		for s in seats:
			s.set_active(false)
	if not game.is_my_turn() or game.finished:
		_cancel_targeting()
	defense_panel.visible = not game.pending_attack.is_empty() and int(game.pending_attack["target"]) == 0
	var shop_open := game.is_my_turn() and game.step == GameController.Step.PHASE1 		and game.pending_attack.is_empty() and game.minigame == null and not game.in_opening() 		and not game.is_held()
	shop_button.visible = shop_open
	if not shop_open:
		shop_panel.visible = false
		_replacing = -1
	elif shop_panel.visible:
		_fill_shop()
	_update_action_button()
	_update_gold()
	_fill_hand()
	_update_self_effects()


func _update_action_button() -> void:
	action_button.visible = game.is_my_turn() and game.pending_attack.is_empty() and game.minigame == null 		and not game.is_held() \
		and not game.in_opening()
	match game.step:
		GameController.Step.ROLL:
			action_button.text = "ทอยลูกเต๋า"
		GameController.Step.PHASE1:
			action_button.text = "ไป Combat →"
		GameController.Step.PHASE2:
			action_button.text = "จบเทิร์น"


func _on_rolled(seat: int, dice: Array[int], gold: int, drawn: Array[String], unlucky: bool) -> void:
	var p := game.players[seat]
	var roll_time := GameController.ROLL_SECONDS / game.speed
	tavern.throw_dice(seat, dice, roll_time)
	action_button.visible = false
	_show_roll_result(p, dice, gold, drawn, unlucky, roll_time)


## Big result card over the dice once they land: dice faces, "+N เงิน", cards drawn.
func _show_roll_result(p: PlayerData, dice: Array[int], gold: int, drawn: Array[String],
		unlucky: bool, delay: float) -> void:
	roll_title.text = ("คุณทอยได้" if game.is_me(p) else "%s ทอยได้" % p.display_name) 		+ "  (รวม %d)" % (dice[0] + dice[1] + dice[2])
	for i in 3:
		roll_dice[i].value = dice[i]
	roll_gold.text = "+%d เงิน" % gold + ("   (ดวงซวย −1)" if unlucky else "")
	if not game.is_me(p):
		roll_cards.text = "จั่วการ์ด %d ใบ" % drawn.size()
	elif drawn.is_empty():
		roll_cards.text = "มือเต็ม จั่วการ์ดไม่ได้"
	else:
		roll_cards.text = "ได้การ์ด: " + ", ".join(drawn)
	if _roll_tween:
		_roll_tween.kill()
	roll_panel.modulate.a = 0.0
	roll_panel.scale = Vector2(0.85, 0.85)
	roll_panel.visible = true
	_roll_tween = create_tween()
	_roll_tween.tween_interval(delay)
	_roll_tween.tween_property(roll_panel, "modulate:a", 1.0, 0.18)
	_roll_tween.parallel().tween_property(roll_panel, "scale", Vector2.ONE, 0.18) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_interval(2.0 / game.speed)
	_roll_tween.tween_property(roll_panel, "modulate:a", 0.0, 0.4)
	_roll_tween.tween_callback(func() -> void: roll_panel.visible = false)


## Your gold, big, under your seat panel. Pops when the amount changes.
func _build_gold_counter() -> void:
	gold_panel = PanelContainer.new()
	gold_panel.position = Vector2(MARGIN, 479)  # level with the buttons (466-524)
	gold_panel.custom_minimum_size = Vector2(140, 32)
	gold_panel.size = Vector2(140, 32)
	gold_panel.pivot_offset = gold_panel.size / 2
	var style := UiStyle.panel(UiStyle.WOOD_DARK, UiStyle.RING.darkened(0.2), 2, 16)
	style.set_content_margin_all(4)
	style.content_margin_left = 10
	gold_panel.add_theme_stylebox_override("panel", style)
	gold_panel.tooltip_text = "เงินของคุณ"
	add_child(gold_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_panel.add_child(row)
	row.add_child(CoinView.new())
	gold_label = Label.new()
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.add_theme_color_override("font_color", UiStyle.RING)
	row.add_child(gold_label)
	var balance := Control.new()  # same width as the coin, so the number sits in the pill's centre
	balance.custom_minimum_size = Vector2(22, 0)
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(balance)
	_update_gold()


func _update_gold() -> void:
	if gold_label == null:
		return
	var gold := game.players[0].gold
	if gold == _shown_gold:
		return
	var first := _shown_gold < 0
	_shown_gold = gold
	gold_label.text = str(gold)
	if not first:
		var t := create_tween()
		t.tween_property(gold_panel, "scale", Vector2(1.15, 1.15), 0.1)
		t.tween_property(gold_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func _build_roll_panel() -> void:
	roll_panel = PanelContainer.new()
	roll_panel.position = Vector2(345, 176)
	roll_panel.custom_minimum_size = Vector2(270, 0)
	roll_panel.size = Vector2(270, 150)
	roll_panel.pivot_offset = roll_panel.size / 2
	var style := UiStyle.panel(Color(UiStyle.WOOD_DARK, 0.96), UiStyle.ACTIVE, 3, 12)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	roll_panel.add_theme_stylebox_override("panel", style)
	roll_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_panel.visible = false
	add_child(roll_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_panel.add_child(box)
	roll_title = _roll_label(box, 14, UiStyle.TEXT)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	for i in 3:
		var d := DiceView.new()
		row.add_child(d)
		roll_dice.append(d)
	roll_gold = _roll_label(box, 30, UiStyle.RING)
	roll_gold.add_theme_color_override("font_outline_color", Color.BLACK)
	roll_gold.add_theme_constant_override("outline_size", 6)
	roll_cards = _roll_label(box, 13, UiStyle.TEXT_DIM)
	roll_cards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _roll_label(parent: Container, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


# ---------- building the screen ----------

func _build_table() -> void:
	tavern = TavernView.new()
	tavern.position = Vector2.ZERO
	tavern.size = Vector2(960, 540)
	add_child(tavern)
	status_fx = Vignette.new(Color.BLACK)
	status_fx.size = Vector2(960, 540)
	add_child(status_fx)
	hit_fx = Vignette.new(Color.RED)
	hit_fx.size = Vector2(960, 540)
	add_child(hit_fx)

	var logo := Label.new()
	logo.text = "Roulette Fantasy"
	logo.position = Vector2(MARGIN, 22)  # level with the player cards
	logo.add_theme_font_size_override("font_size", 20)
	logo.add_theme_color_override("font_color", UiStyle.ACTIVE)
	logo.add_theme_color_override("font_outline_color", Color("2a1408"))
	logo.add_theme_constant_override("outline_size", 8)
	logo.visible = not SeatPanel.compact  # 5-6 player cards need the whole bar
	add_child(logo)

	for i in _seat_count:
		var seat := SeatPanel.new()
		seat.position = _slot_rect(i).position
		seat.custom_minimum_size = _slot_rect(i).size
		add_child(seat)
		seats.append(seat)

	# under the dice, like the round/phase plate in the mockup
	# round/phase plate under the top bar, whose turn under it
	var plate := PanelContainer.new()
	var plate_style := UiStyle.panel(Color(0.08, 0.06, 0.05, 0.85), UiStyle.BRASS.darkened(0.2), 1, 14)
	plate_style.content_margin_left = 18
	plate_style.content_margin_right = 18
	plate_style.content_margin_top = 3
	plate_style.content_margin_bottom = 3
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.position = Vector2(355, 76)
	plate.custom_minimum_size = Vector2(250, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	round_label = Label.new()
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 15)
	round_label.add_theme_color_override("font_color", UiStyle.TEXT)
	plate.add_child(round_label)
	# whose turn, and the seconds left beside it, as one line centred under the plate
	var turn_row := HBoxContainer.new()
	turn_row.position = Vector2(300, 103)
	turn_row.size = Vector2(360, 26)
	turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_row.add_theme_constant_override("separation", 12)
	turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(turn_row)
	phase_label = _center_label(Vector2.ZERO, 12)
	phase_label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	phase_label.reparent(turn_row)
	phase_label.size = Vector2.ZERO
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	showdown_plate = PanelContainer.new()
	var sp := UiStyle.panel(Color(0.07, 0.04, 0.03, 0.82), Color("ff8a3c"), 1, 8)
	sp.content_margin_top = 1
	sp.content_margin_bottom = 1
	sp.content_margin_left = 10
	sp.content_margin_right = 10
	showdown_plate.add_theme_stylebox_override("panel", sp)
	showdown_plate.position = Vector2(400, 126)
	showdown_plate.mouse_filter = Control.MOUSE_FILTER_PASS  # for its tooltip
	add_child(showdown_plate)
	showdown_label = Label.new()
	showdown_label.add_theme_font_size_override("font_size", 13)
	showdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showdown_plate.add_child(showdown_label)

	turn_bar = TurnTimerBar.new()
	add_child(turn_bar)

	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.tooltip_text = "เวลาที่เหลือ (วินาที.มิลลิวินาที)"
	time_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New"])  # fixed-width digits don't jitter
	time_label.add_theme_font_override("font", mono)
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	time_label.add_theme_constant_override("outline_size", 3)
	turn_row.add_child(time_label)

	action_button = _brass_button(Vector2(960 - MARGIN - 148, 466), Vector2(148, 58))
	action_button.add_theme_font_size_override("font_size", 19)
	action_button.pressed.connect(func() -> void: game.advance())
	shop_button = _brass_button(Vector2(960 - MARGIN - 148 - 8 - 112, 466), Vector2(112, 58))
	shop_button.add_theme_font_size_override("font_size", 19)
	shop_button.text = "ร้านค้า"
	shop_button.pressed.connect(func() -> void:
		shop_panel.visible = not shop_panel.visible
		if shop_panel.visible:
			_fill_shop()
		else:
			_cancel_replace())


## Top right: a dice button; hover (or click to keep it open) shows how a roll scores.
func _build_dice_tip() -> void:
	var b := _brass_button(Vector2(960 - MARGIN - 44, 17), Vector2(44, 44))  # level with the player cards
	b.icon = Icons.get_icon("dice")
	b.add_theme_constant_override("icon_max_width", 24)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var mark := Label.new()  # a small "?" in the corner: it's help
	mark.text = "?"
	mark.position = Vector2(30, 22)
	mark.add_theme_font_size_override("font_size", 13)
	mark.add_theme_color_override("font_color", UiStyle.ACTIVE)
	mark.add_theme_color_override("font_outline_color", Color.BLACK)
	mark.add_theme_constant_override("outline_size", 4)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(mark)

	dice_tip = PanelContainer.new()
	var style := UiStyle.panel(Color(UiStyle.WOOD_DARK, 0.97), UiStyle.BRASS, 2, 10)
	style.set_content_margin_all(12)
	dice_tip.add_theme_stylebox_override("panel", style)
	dice_tip.position = Vector2(960 - MARGIN - 346, 66)
	dice_tip.custom_minimum_size = Vector2(346, 0)
	dice_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_tip.z_index = 95
	dice_tip.visible = false
	add_child(dice_tip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	dice_tip.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(Icons.rect("dice", 20))
	head.add_child(_tip_label("การนับแต้มลูกเต๋า", 16, UiStyle.ACTIVE))
	box.add_child(_tip_label("ทอยลูกเต๋า 3 ลูก แล้ว รวมแต้ม ÷ 2 (ปัดเศษลง) = เงินที่ได้", 13, UiStyle.TEXT))
	box.add_child(_tip_label("ตัวอย่าง  4 + 5 + 2 = 11  →  ได้ 5 เงิน", 13, UiStyle.TEXT_DIM))
	# every total and what it pays, in two rows
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	var totals := ["3", "4-5", "6-7", "8-9", "10-11", "12-13", "14-15", "16-17", "18"]
	grid.add_child(_tip_label("รวม", 11, UiStyle.TEXT_DIM))
	for t: String in totals:
		grid.add_child(_tip_label(t, 11, UiStyle.TEXT))
	grid.add_child(_tip_label("เงิน", 11, UiStyle.TEXT_DIM))
	for g in range(1, GameController.MAX_ROLL_GOLD + 1):
		grid.add_child(_tip_label(str(g), 13, UiStyle.ACTIVE))
	box.add_child(_tip_label("• ได้น้อยสุด 1 เงิน · มากสุด %d เงิน (6 + 6 + 6)" % GameController.MAX_ROLL_GOLD, 12, UiStyle.TEXT))
	box.add_child(_tip_label("• ทอยแล้วจั่วการ์ดเพิ่ม %d ใบทุกครั้ง" % GameController.DRAW_PER_TURN, 12, UiStyle.TEXT))
	var luck := HBoxContainer.new()
	luck.add_theme_constant_override("separation", 4)
	box.add_child(luck)
	luck.add_child(Icons.rect("bad_luck", 16))
	luck.add_child(_tip_label("ดวงซวย: เงินลดลง 1 (ถ้าทอยได้ %d จะเหลือ 1)" % GameController.MAX_ROLL_GOLD, 12, Color("c9a0f0")))

	b.mouse_entered.connect(func() -> void: dice_tip.visible = true)
	b.mouse_exited.connect(func() -> void: dice_tip.visible = _dice_tip_pinned)
	b.pressed.connect(func() -> void:
		_dice_tip_pinned = not _dice_tip_pinned
		dice_tip.visible = _dice_tip_pinned or b.is_hovered())


func _tip_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if font_size <= 13 and text.length() <= 5 else HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _brass_button(pos: Vector2, min_size: Vector2) -> Button:
	var b := Button.new()
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel icons stay crisp
	b.add_theme_constant_override("icon_max_width", 26)
	b.position = pos
	b.custom_minimum_size = min_size
	b.add_theme_stylebox_override("normal", UiStyle.panel(UiStyle.BRASS.darkened(0.3), UiStyle.BRASS, 2, 6))
	b.add_theme_stylebox_override("hover", UiStyle.panel(UiStyle.BRASS.darkened(0.1), UiStyle.ACTIVE, 2, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.panel(UiStyle.BRASS.darkened(0.45), UiStyle.BRASS, 2, 6))
	b.add_theme_stylebox_override("disabled", UiStyle.panel(UiStyle.WOOD_DARK, UiStyle.TEXT_DIM, 1, 6))
	add_child(b)
	return b


func _center_label(pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(260, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)  # readable over the 3D room
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


const CARD_SIZE := Vector2(72, 104)
const CARD_STEP := 50.0  # cards overlap like a hand of cards; only the left strip shows
const CARD_LIFT := 22.0  # how far the card under the mouse rises
const FAN_ANGLE := 0.07  # radians between neighbouring cards
const HAND_BOX := Rect2(275, 400, 410, 132)
const RAIL_ENDS: Array[float] = [300.0, 660.0]  # mirror images about the middle (480)


func _build_hand() -> void:
	# a brass rail behind the hand, centred on it, between your gold and the buttons, with a
	# diamond at each end
	var rail := ColorRect.new()
	rail.color = Color(UiStyle.BRASS, 0.7)
	rail.position = Vector2(RAIL_ENDS[0], 494)
	rail.size = Vector2(RAIL_ENDS[1] - RAIL_ENDS[0], 2)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)
	for x: float in RAIL_ENDS:
		var gem := ColorRect.new()
		gem.color = UiStyle.BRASS
		gem.size = Vector2(8, 8)
		gem.pivot_offset = Vector2(4, 4)
		gem.position = Vector2(x - 4, 491)
		gem.rotation = PI / 4
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(gem)

	hand_box = Control.new()
	hand_box.position = HAND_BOX.position
	hand_box.size = HAND_BOX.size
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hand_box)

	hand_lock = HBoxContainer.new()
	hand_lock.position = Vector2(HAND_BOX.get_center().x - 80, HAND_BOX.position.y - 6)
	hand_lock.size = Vector2(160, 28)
	(hand_lock as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	hand_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_lock.z_index = 80
	hand_lock.visible = false
	hand_hint = Label.new()
	hand_hint.position = Vector2(HAND_BOX.get_center().x - 300, HAND_BOX.position.y - 40)
	hand_hint.size = Vector2(600, 30)
	hand_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_hint.add_theme_font_size_override("font_size", 16)
	hand_hint.add_theme_color_override("font_color", Color("ff8a7a"))
	hand_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hand_hint.add_theme_constant_override("outline_size", 6)
	hand_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_hint.z_index = 85
	hand_hint.modulate.a = 0.0
	add_child(hand_hint)
	hand_lock.add_child(Icons.rect("no_items", 24))
	var lock_text := Label.new()
	lock_text.text = "ห้ามใช้ไอเทม"
	lock_text.add_theme_color_override("font_color", Color("e0b8ff"))
	lock_text.add_theme_color_override("font_outline_color", Color.BLACK)
	lock_text.add_theme_constant_override("outline_size", 5)
	hand_lock.add_child(lock_text)

	# you have no body to click: a card that may target you gets this button over the hand
	self_target_button = Button.new()
	self_target_button.text = "  ใช้กับตัวเอง  "
	self_target_button.icon = Icons.get_icon("star")
	self_target_button.add_theme_constant_override("icon_max_width", 18)
	self_target_button.custom_minimum_size = Vector2(170, 36)
	self_target_button.position = Vector2(HAND_BOX.get_center().x - 85, HAND_BOX.position.y - 50)
	self_target_button.add_theme_stylebox_override("normal", UiStyle.panel(Color(0.07, 0.17, 0.27, 0.95), SeatPanel.MINE_BORDER, 2, 8))
	self_target_button.add_theme_stylebox_override("hover", UiStyle.panel(Color(0.1, 0.25, 0.38, 0.98), UiStyle.ACTIVE, 2, 8))
	self_target_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	self_target_button.z_index = 90
	self_target_button.visible = false
	self_target_button.pressed.connect(func() -> void: _on_seat_clicked(0))
	add_child(self_target_button)
	add_child(hand_lock)


func _fill_hand() -> void:
	for child in hand_box.get_children():
		hand_box.remove_child(child)
		child.queue_free()
	var me := game.players[0]
	_hand_map.assign(range(me.hand.size()))
	var blind := me.has("blind")
	if blind:
		_hand_map.shuffle()  # cards hidden and moved around
	var n := _hand_map.size()
	var left := (HAND_BOX.size.x - (n - 1) * CARD_STEP - CARD_SIZE.x) / 2
	for i in n:
		var hand_index := _hand_map[i]
		var card := me.hand[hand_index]
		var b := _card_button(card, blind)
		# fanned out: tilted round the bottom centre, outer cards a little lower
		var off := i - (n - 1) / 2.0
		b.pivot_offset = Vector2(CARD_SIZE.x / 2, CARD_SIZE.y)
		b.rotation = off * FAN_ANGLE
		b.set_meta("base_y", CARD_LIFT + off * off * 2.0)
		b.position = Vector2(left + i * CARD_STEP, b.get_meta("base_y"))
		b.z_index = i
		if _replacing >= 0:
			b.add_theme_stylebox_override("normal", UiStyle.panel(_card_color(card, blind), Color("ff6b6b"), 3, 6))
			b.tooltip_text = "คลิกเพื่อทิ้งใบนี้แลกการ์ดที่ซื้อ"
		if not _targeting.is_empty() and _targeting["index"] == hand_index:
			b.add_theme_stylebox_override("normal", UiStyle.panel(_card_color(card, blind), SeatPanel.TARGET, 4, 6))
			_lift(b, true, i)
		b.pressed.connect(_on_card_pressed.bind(hand_index))
		b.mouse_entered.connect(_lift.bind(b, true, i))
		b.mouse_exited.connect(func() -> void:
			var targeted: bool = not _targeting.is_empty() and _targeting["index"] == hand_index
			_lift(b, targeted, i))
		hand_box.add_child(b)


## Raise a card above its neighbours (hover / selected) or drop it back into the fan.
func _lift(b: Button, up: bool, order: int) -> void:
	b.z_index = 50 if up else order
	var base: float = b.get_meta("base_y", CARD_LIFT)
	var t := b.create_tween()
	t.tween_property(b, "position:y", base - CARD_LIFT if up else base, 0.1).set_trans(Tween.TRANS_SINE)


## Card body colour: its type colour, dark enough for light text (gold back when hidden).
func _card_color(card: Dictionary, hidden: bool) -> Color:
	if hidden:
		return Color("27306b")
	return UiStyle.TYPE_COLORS.get(card["type"], UiStyle.WOOD).darkened(0.25)


func _card_button(card: Dictionary, hidden: bool) -> Button:
	var b := Button.new()
	b.size = CARD_SIZE
	b.custom_minimum_size = CARD_SIZE
	b.tooltip_text = "ตาบอด: มองไม่เห็นการ์ด" if hidden else "%s
%s" % [card["name"], card.get("desc", "")]
	var body := _card_color(card, hidden)
	var edge := UiStyle.BRASS if hidden else body.lightened(0.45)
	b.add_theme_stylebox_override("normal", UiStyle.panel(body, edge, 3, 6))
	b.add_theme_stylebox_override("hover", UiStyle.panel(body.lightened(0.12), UiStyle.ACTIVE, 3, 6))
	b.add_theme_stylebox_override("pressed", UiStyle.panel(body.darkened(0.1), UiStyle.ACTIVE, 3, 6))
	# like a real card: the name across the top, the picture in the middle
	var name_label := Label.new()
	name_label.text = "?" if hidden else game.card_name(game.players[0], card)
	name_label.position = Vector2(6, 3)
	# wrap first: with wrapping off, a Label can't be narrower than its text
	name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY  # Thai has no spaces to wrap at
	name_label.size = Vector2(CARD_SIZE.x - 10, 30)
	name_label.add_theme_color_override("font_color", UiStyle.TEXT)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_constant_override("line_spacing", -4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_label)
	var art := Icons.rect("blind", 40) if hidden else Icons.rect(game.card_icon(game.players[0], card), 48)
	if hidden:
		art.modulate = Color(1, 1, 1, 0.5)
	art.position = Vector2((CARD_SIZE.x - art.size.x) / 2, 38)
	b.add_child(art)
	return b


# ---------- hit effects ----------


## A card was played: throw it across the room from the player to the target. Attack cards
## aren't thrown: the attacker's character attack plays when the attack resolves.
func _on_card_played(seat: int, target: int, card: Dictionary) -> void:
	if card["id"] == "attack":
		return
	sfx.play("card_play")
	var flight := TavernView.CARD_FLIGHT / game.speed
	tavern.throw_card(seat, target, card, flight)
	_card_lands_ms = Time.get_ticks_msec() + int(flight * 1000.0)


## An attack resolved: the attacker's character attack plays (move name at the top), and
## the hit/block effects come when it lands. If the hit knocks the target out, the
## character's finisher follows and the target's knockout pose waits for it.
func _on_attacked(attacker: int, target: int, blocked: bool) -> void:
	var who := game.players[attacker]
	var c := CharacterDB.get_character(who.character)
	if c.is_empty():
		_attack_fx(attacker, target, blocked, "")
		return
	var finisher := not blocked and game.players[target].hp <= 0
	# once you're out the bots play on faster; the blow that ends the game always plays at
	# full length, so you see it
	var game_ending := finisher and game.alive_players().size() <= 2
	var k := 1.0 if game_ending and not game.autoplay else 1.0 / game.speed
	if finisher:  # the hand is cleared when they're knocked out: remember how many to drop
		_dying_cards[target] = game.players[target].hand.size()
	var you_die := finisher and target == 0
	if you_die:  # your hero sits down in your seat and the camera pulls out to watch it all
		var watch: float = AttackFx.IMPACT[c["style"]] * k + tavern.finisher_time(c["style"], k) + 0.6 * k
		tavern.watch_your_death(game.players[0].character, watch - TavernView.DEATH_GLIDE_OUT * k, k)
	var impact := tavern.play_attack(attacker, target, c["style"], finisher, k)
	_show_move(who, c, finisher)
	var ends := impact + (tavern.finisher_time(c["style"], k) if finisher else 0.3 * k)
	if you_die:
		ends += (0.6 + TavernView.DEATH_GLIDE_BACK) * k  # ...and glides back to your eyes
	game.hold(ends)  # the game waits for the attack (and finisher) to play out
	if finisher:
		_ko_until_ms[target] = Time.get_ticks_msec() + int(ends * 1000.0)
	get_tree().create_timer(maxf(impact, 0.01)).timeout.connect(
		_attack_fx.bind(attacker, target, blocked, c["style"] if finisher else ""))


## "<name>: Blood Slash" at the top of the table; a finisher gets a big red banner.
func _show_move(who: PlayerData, c: Dictionary, finisher: bool) -> void:
	move_label.text = ("%s!" % c["finisher"].to_upper()) if finisher else "%s · %s" % [who.display_name, c["attack"]]
	move_label.add_theme_font_size_override("font_size", 40 if finisher else 18)
	move_label.add_theme_color_override("font_color", Color("ff5a4f") if finisher else UiStyle.ACTIVE)
	move_label.modulate.a = 0.0
	var t := move_label.create_tween()
	t.tween_property(move_label, "modulate:a", 1.0, 0.12)
	t.tween_interval(0.8 / game.speed)  # gone before a finisher's big moment (Final Arrow's strike)
	t.tween_property(move_label, "modulate:a", 0.0, 0.4)


## `finisher_style` is set when this hit is a knockout finisher (the tavern plays the body
## effects; on you, the screen shows it).
func _attack_fx(_attacker: int, target: int, blocked: bool, finisher_style := "") -> void:
	var seat := seats[target]
	var r := seat.get_rect()
	if finisher_style == "":
		sfx.play("block" if blocked else "hurt")
	if finisher_style != "":
		_flash(r, Color(1.0, 0.15, 0.1, 0.5))
		# the dead player's cards fall onto the table (a held fan of 4 if their hand was empty)
		var held: int = _dying_cards.get(target, 0)
		tavern.drop_cards(target, held if held > 0 else 4, 1.0 / game.speed)
		return
	if target == 0:
		_on_you_attacked(blocked)
	elif blocked:
		tavern.block(target)  # the shield shows at the bot itself
		_flash(r, Color(0.35, 0.65, 1.0, 0.3))
	else:
		tavern.hit(target)
		_flash(r, Color(1.0, 0.15, 0.1, 0.35))
		_shake(seat)


## Your own view: a red edge flash and a jolt when hit, a big shield and blue edges on a block.
func _on_you_attacked(blocked: bool) -> void:
	var r := seats[0].get_rect()
	if blocked:
		hit_fx.flash(Color(0.3, 0.6, 1.0), 0.8)
		var shield := Icons.rect("defense", 96)
		shield.position = Vector2(480 - 48, 200)
		shield.pivot_offset = Vector2(48, 48)
		shield.scale = Vector2(0.4, 0.4)
		add_child(shield)
		var t := shield.create_tween()
		t.tween_property(shield, "scale", Vector2(1.15, 1.15), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(shield, "scale", Vector2.ONE, 0.1)
		t.tween_interval(0.5)
		t.tween_property(shield, "modulate:a", 0.0, 0.35)
		t.tween_callback(shield.queue_free)
	else:
		hit_fx.flash(Color(1.0, 0.1, 0.05), 0.75)
		_shake(tavern)
		_shake(seats[0])
		_float_text(Rect2(r.position + Vector2(0, r.size.y + 30), r.size), "-1 เลือด", UiStyle.HP)  # below your card


## Under the round plate: just the number of rounds left until everyone's max HP and hand
## limit drop (orange on the last round); gone once both are as low as they go.
func _update_showdown_label() -> void:
	if game.finished or game.in_opening():
		showdown_plate.visible = false
		return
	showdown_plate.visible = game.shrinking()
	var text := str(game.shrink_in)
	showdown_label.add_theme_color_override("font_color", Color("ff8a3c") if game.shrink_in == 1 else UiStyle.ACTIVE)
	showdown_plate.tooltip_text = "อีก %d รอบ เลือดสูงสุดและการ์ดในมือสูงสุดของทุกคนจะลดลง 1\n(ตอนนี้ เลือดสูงสุด %d · การ์ดในมือสูงสุด %d)" % [
		game.shrink_in, game.max_hp, game.hand_limit]
	if text != showdown_label.text:
		showdown_label.text = text
		showdown_plate.reset_size()
		showdown_plate.position.x = 480 - showdown_plate.size.x / 2


## Max HP and the hand limit just dropped: a warm flash and the cards redraw.
func _on_showdown_shrunk() -> void:
	SeatPanel.hp_max = game.max_hp
	hit_fx.flash(Color(1.0, 0.45, 0.05), 0.45)
	_float_text(Rect2(Vector2(330, 150), Vector2(300, 40)), "เลือดสูงสุด %d · การ์ดในมือสูงสุด %d" % [game.max_hp, game.hand_limit], Color("ff8a3c"))
	refresh_all()


## Lasting effects on you, shown where they bite: blind = dark purple haze, truce = soft blue
## edges, no items = your hand greyed with a badge, no shop = shop button marked, bad luck =
## a black cat on the roll button.
func _update_self_effects() -> void:
	var me := game.players[0]
	var target := 0.0
	if me.has("blind"):
		status_fx.set_tint(Color("2a0f3d"))
		target = 0.85
	elif me.has("truce"):
		status_fx.set_tint(Color("4fa3ff"))
		target = 0.35
	if not is_equal_approx(status_fx.strength, target):
		create_tween().tween_property(status_fx, "strength", target, 0.4)
	var locked := me.has("no_items")
	hand_box.modulate = Color(0.5, 0.5, 0.58) if locked else Color.WHITE
	hand_lock.visible = locked and not me.hand.is_empty()
	shop_button.icon = Icons.get_icon("no_shop" if me.has("no_shop") else "shop")
	shop_button.tooltip_text = "โดนคำสาป ห้ามซื้อของ" if me.has("no_shop") else ""
	var unlucky := me.has("bad_luck") and game.step == GameController.Step.ROLL
	var step_icon: String = {GameController.Step.ROLL: "dice", GameController.Step.PHASE1: "swords",
		GameController.Step.PHASE2: "turn"}[game.step]
	action_button.icon = Icons.get_icon("bad_luck" if unlucky else step_icon)
	action_button.tooltip_text = "ดวงซวย: ทอยครั้งนี้ได้ผลต่ำลง 1 ระดับ" if unlucky else ""


func _flash(r: Rect2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = r.position
	rect.size = r.size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	var t := rect.create_tween()
	t.tween_property(rect, "color:a", 0.0, 0.5)
	t.tween_callback(rect.queue_free)


func _float_text(r: Rect2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.size = Vector2(r.size.x, 30)
	label.position = Vector2(r.position.x, r.get_center().y - 15)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color.lightened(0.2))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var t := label.create_tween()
	t.tween_property(label, "position:y", label.position.y - 34, 0.9).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	t.tween_callback(label.queue_free)


func _shake(node: Control) -> void:
	var home := node.position
	var t := node.create_tween()
	for dx: float in [-7.0, 7.0, -5.0, 5.0, -2.0]:
		t.tween_property(node, "position", home + Vector2(dx, 0), 0.04)
	t.tween_property(node, "position", home, 0.04)


# ---------- playing cards ----------

func _on_card_pressed(hand_index: int) -> void:
	var me := game.players[0]
	if _replacing >= 0:
		var slot := _replacing
		_replacing = -1
		game.buy(me, slot, hand_index)
		refresh_all()
		return
	if not _targeting.is_empty():
		var same: bool = _targeting["index"] == hand_index
		_cancel_targeting()
		if same:
			add_log("ยกเลิกการเลือกเป้าหมาย")
			return
	var card := me.hand[hand_index]
	var reason := game.can_play(me, card)
	if reason != "":
		add_log("[color=#ff6b6b]%s[/color]" % reason)
		_flash_hint(reason)
		return
	if card["target"] in ["enemy", "any"]:
		_targeting = {"index": hand_index, "card": card}
		for seat in game.valid_targets(me, card):
			seats[seat].set_targetable(true)
			tavern.set_targetable(seat, true)
		self_target_button.visible = 0 in game.valid_targets(me, card)
		add_log("เลือกเป้าหมายของ [b]%s[/b]: คลิกที่ตัวละครหรือป้ายผู้เล่น%s (คลิกการ์ดเดิมหรือ Esc เพื่อยกเลิก)" % [
			card["name"], " หรือกด \"ใช้กับตัวเอง\"" if self_target_button.visible else ""])
		_fill_hand()
	else:
		game.play_card(me, hand_index)


## `text` over your hand for a moment (the history may be folded away).
func _flash_hint(text: String) -> void:
	hand_hint.text = text
	if _hint_tween:
		_hint_tween.kill()
	hand_hint.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.tween_interval(1.8)
	_hint_tween.tween_property(hand_hint, "modulate:a", 0.0, 0.4)


func _on_seat_clicked(seat: int) -> void:
	if _targeting.is_empty():
		return
	var index: int = _targeting["index"]
	_cancel_targeting()
	game.play_card(game.players[0], index, seat)


func _cancel_targeting() -> void:
	if _targeting.is_empty():
		return
	_targeting = {}
	self_target_button.visible = false
	for s in seats:
		s.set_targetable(false)
		tavern.set_targetable(s.player.seat, false)
	tavern.set_hover(-1)
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _cancel_replace() -> void:
	if _replacing < 0:
		return
	_replacing = -1
	if shop_panel.visible:
		_fill_shop()
	_fill_hand()


## Clicks and hovering on the 3D room (nothing else on the HUD took them): while you pick a
## target, the bot under the mouse lights up and a click picks it.
func _gui_input(event: InputEvent) -> void:
	if _targeting.is_empty():
		return
	if event is InputEventMouseMotion:
		var over := tavern.seat_at(event.position)
		var ok := over > 0 and seats[over]._targetable
		tavern.set_hover(over if ok else -1)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ok else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var seat := tavern.seat_at(event.position)
		if seat > 0 and seats[seat]._targetable:
			_on_seat_clicked(seat)
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _replacing >= 0:
		_cancel_replace()
	elif event.is_action_pressed("ui_cancel") and not _targeting.is_empty():
		_cancel_targeting()
		add_log("ยกเลิกการเลือกเป้าหมาย")
		_fill_hand()


func _on_attack_incoming(attacker: int, target: int) -> void:
	if target != 0:
		return  # online: someone else decides whether to block
	var free: bool = game.players[target].has("free_block")
	defense_label.text = "%s โจมตีคุณ!\nใช้การ์ดป้องกันไหม?%s" % [game.players[attacker].display_name,
		"\n(ป้องกันฟรี: การ์ดไม่หาย)" if free else ""]
	defense_panel.visible = true


const RESULT_WAIT_SECONDS := 3.0  # the win banner stays this long before the summary


## Once the last finisher has played out, "<name> ชนะ!" for RESULT_WAIT_SECONDS, then the
## summary table.
func _on_game_over(winner: int) -> void:
	var now := Time.get_ticks_msec()
	var finisher_left := 0.0
	for until: int in _ko_until_ms.values():
		finisher_left = maxf(finisher_left, (until - now) / 1000.0)
	var t := create_tween()
	t.tween_interval(finisher_left)
	t.tween_callback(func() -> void:
		banner.text = "%s ชนะ!" % game.players[winner].display_name
		banner.visible = true
		sfx.play("win" if winner == 0 else "lose"))
	t.tween_interval(RESULT_WAIT_SECONDS / (game.speed if game.autoplay else 1.0))  # full wait, even spectating
	t.tween_callback(func() -> void:
		banner.visible = false
		result_panel.show_result(game, winner))


func _build_minigame_and_result() -> void:
	minigame_panel = MinigamePanel.new()
	minigame_panel.position = Vector2(140, 30)  # centred over the table; clear of the open log
	minigame_panel.size = Vector2(680, 420)
	add_child(minigame_panel)
	minigame_panel.setup(game)
	result_panel = ResultPanel.new()
	result_panel.size = Vector2(960, 540)
	add_child(result_panel)


func _build_defense_panel() -> void:
	defense_panel = PanelContainer.new()
	defense_panel.position = Vector2(370, 150)
	defense_panel.custom_minimum_size = Vector2(220, 120)
	defense_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.WOOD_DARK, SeatPanel.TARGET, 3, 10))
	defense_panel.visible = false
	add_child(defense_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	defense_panel.add_child(box)
	defense_label = Label.new()
	defense_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(defense_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for spec: Array in [["ป้องกัน", true], ["ไม่ป้องกัน", false]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(90, 30)
		var use: bool = spec[1]
		b.pressed.connect(func() -> void: game.respond_defense(use))
		row.add_child(b)


func _build_shop() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.position = Vector2(240, 112)  # under the top bar, centred (_fill_shop)
	shop_panel.custom_minimum_size = Vector2(480, 0)
	shop_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.WOOD_DARK, UiStyle.BRASS, 3, 10))
	shop_panel.visible = false
	add_child(shop_panel)
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 6)
	shop_panel.add_child(shop_list)


func _fill_shop() -> void:
	var me := game.players[0]
	for child in shop_list.get_children():
		shop_list.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "ร้านค้า · เงินของคุณ %d · การ์ดในมือ %d/%d" % [me.gold, me.hand.size(), game.hand_limit] 		+ ("  (เต็ม: ซื้อแล้วต้องทิ้ง 1 ใบ)" if game.hand_full(me) else "")
	title.add_theme_color_override("font_color", UiStyle.BRASS)
	shop_list.add_child(title)
	if _replacing >= 0:
		var pick_row := HBoxContainer.new()
		pick_row.add_theme_constant_override("separation", 8)
		shop_list.add_child(pick_row)
		var pick := Label.new()
		pick.text = "เลือกการ์ดในมือ (ด้านล่าง) ที่จะทิ้ง เพื่อรับ %s" % game.shop[_replacing]["name"]
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.add_theme_color_override("font_color", Color("ff6b6b"))
		pick_row.add_child(pick)
		var cancel := Button.new()
		cancel.text = "ยกเลิก"
		cancel.custom_minimum_size = Vector2(90, 26)
		cancel.pressed.connect(_cancel_replace)
		pick_row.add_child(cancel)
	if me.has("no_shop"):
		var cursed := Label.new()
		cursed.text = "คุณโดนคำสาป ห้ามซื้อของ"
		cursed.add_theme_color_override("font_color", Color("c9a0ff"))
		shop_list.add_child(cursed)
	for slot in game.shop.size():
		var card := game.shop[slot]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		shop_list.add_child(row)
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(120, 0)
		var desc := Label.new()
		desc.custom_minimum_size = Vector2(200, 0)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		var b := Button.new()
		b.custom_minimum_size = Vector2(90, 26)
		if card.is_empty():
			name_label.text = "— ขายแล้ว —"
			name_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
			b.text = "-"
			b.disabled = true
		else:
			name_label.text = game.card_name(me, card)
			name_label.add_theme_color_override("font_color", UiStyle.TYPE_COLORS.get(card["type"], UiStyle.TEXT).lightened(0.35))
			desc.text = card.get("desc", "")
			b.text = "ซื้อ %d เงิน" % card["price"]
			var reason := game.can_buy(me, slot)
			b.disabled = reason != "" or slot == _replacing
			b.tooltip_text = reason if reason != "" else ("มือเต็ม: ซื้อแล้วเลือกการ์ดที่จะทิ้ง" if game.hand_full(me) else "")
			b.pressed.connect(func() -> void:
				if game.hand_full(me):
					_replacing = slot  # wait for a hand card to swap out
					_fill_shop()
					_fill_hand()
				else:
					game.buy(me, slot))
		var icon := Icons.rect("" if card.is_empty() else game.card_icon(me, card), 24)
		row.add_child(icon)
		row.add_child(name_label)
		row.add_child(desc)
		row.add_child(b)
	if game.rings_to_win <= 0:
		return  # rings off: nothing to exchange
	var ring_row := HBoxContainer.new()
	ring_row.add_theme_constant_override("separation", 8)
	shop_list.add_child(ring_row)
	var ring_label := Label.new()
	ring_label.text = "แลกแหวน: เศษแหวน %d ชิ้น → แหวน 1 วง (มีเศษ %d)" % [GameController.SHARDS_PER_RING, me.shards]
	ring_label.custom_minimum_size = Vector2(358, 0)
	ring_label.add_theme_color_override("font_color", UiStyle.RING)
	ring_row.add_child(ring_label)
	var rb := Button.new()
	rb.text = "แลกแหวน"
	rb.custom_minimum_size = Vector2(90, 26)
	var ring_reason := game.can_exchange(me)
	rb.disabled = ring_reason != ""
	rb.tooltip_text = ring_reason
	rb.pressed.connect(func() -> void: game.exchange_ring(me))
	ring_row.add_child(rb)
	if ring_reason != "" and me.shards >= GameController.SHARDS_PER_RING or game.minigames_played < 1:
		var why := Label.new()
		why.text = ring_reason
		why.add_theme_font_size_override("font_size", 12)
		why.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		shop_list.add_child(why)
	var close := Button.new()
	close.text = "ปิดร้าน"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void:
		shop_panel.visible = false
		_cancel_replace())
	shop_list.add_child(close)
	shop_panel.reset_size()
	shop_panel.position.x = 480 - shop_panel.size.x / 2


func _build_turn_toast() -> void:
	turn_toast = Label.new()
	turn_toast.text = "เทิร์นของคุณ!"
	turn_toast.position = Vector2(130, 150)  # 700 wide: centred
	turn_toast.size = Vector2(700, 70)
	turn_toast.pivot_offset = turn_toast.size / 2
	turn_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_toast.add_theme_font_size_override("font_size", 44)
	turn_toast.add_theme_color_override("font_color", UiStyle.ACTIVE)
	turn_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	turn_toast.add_theme_constant_override("outline_size", 10)
	turn_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_toast.modulate.a = 0.0
	add_child(turn_toast)


## "Your turn!" in the middle of the table: pop in, hold, fade out.
func _on_turn_started(_seat: int) -> void:
	if not game.is_my_turn():
		return
	sfx.play("turn")
	turn_toast.modulate.a = 0.0
	turn_toast.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.tween_property(turn_toast, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(turn_toast, "scale", Vector2.ONE, 0.25) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_property(turn_toast, "modulate:a", 0.0, 0.6)


func _build_move_label() -> void:
	move_label = Label.new()
	move_label.position = Vector2(130, 128)
	move_label.size = Vector2(700, 50)
	move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	move_label.add_theme_color_override("font_outline_color", Color.BLACK)
	move_label.add_theme_constant_override("outline_size", 8)
	move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_label.modulate.a = 0.0
	add_child(move_label)


func _build_banner() -> void:
	banner = Label.new()
	banner.position = Vector2(130, 180)
	banner.size = Vector2(700, 60)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_color", UiStyle.ACTIVE)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.visible = false
	add_child(banner)


func _build_log() -> void:
	log_panel = PanelContainer.new()
	log_panel.position = Vector2(960 - MARGIN - 138, 80)
	log_panel.custom_minimum_size = Vector2(138, 300)
	log_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.WOOD_DARK, 0.9), UiStyle.BRASS))
	add_child(log_panel)

	var box := VBoxContainer.new()
	log_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "ประวัติการดำเนินเกม"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UiStyle.BRASS)
	head.add_child(title)
	# fold the history away to see more of the table
	var fold := Button.new()
	fold.text = "▲"
	fold.flat = true
	fold.add_theme_font_size_override("font_size", 10)
	fold.add_theme_color_override("font_color", UiStyle.BRASS)
	fold.tooltip_text = "ย่อ / ขยายประวัติ"
	head.add_child(fold)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel icons in the lines
	log_box.add_theme_font_size_override("normal_font_size", 11)
	log_box.add_theme_constant_override("line_separation", 3)
	box.add_child(log_box)
	# folded, the history becomes a tab on the right edge (starts folded: more table to see)
	log_tab = Button.new()
	log_tab.text = "«  ประวัติการเล่น"
	log_tab.size = Vector2(150, 30)
	log_tab.position = Vector2(930, 305)  # level with the middle of the open log
	log_tab.rotation = -PI / 2
	log_tab.add_theme_font_size_override("font_size", 13)
	log_tab.add_theme_color_override("font_color", UiStyle.BRASS)
	log_tab.add_theme_stylebox_override("normal", UiStyle.panel(Color(UiStyle.WOOD_DARK, 0.92), UiStyle.BRASS, 2, 8))
	log_tab.add_theme_stylebox_override("hover", UiStyle.panel(UiStyle.WOOD, UiStyle.ACTIVE, 2, 8))
	log_tab.tooltip_text = "เปิดประวัติการดำเนินเกม"
	add_child(log_tab)
	fold.text = "»"
	fold.tooltip_text = "ย่อประวัติไปไว้ขอบขวา"
	var show_log := func(on: bool) -> void:
		log_panel.visible = on
		log_tab.visible = not on
	fold.pressed.connect(show_log.bind(false))
	log_tab.pressed.connect(show_log.bind(true))
	show_log.call(false)
