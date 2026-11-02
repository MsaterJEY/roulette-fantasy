extends SceneTree
## Clicking a 3D bot picks it as the target: for each bot, put an Attack card in your hand,
## start targeting, click the middle of that bot's body on screen and check the attack
## landed on that bot. Also checks an empty spot picks nobody, and that a cleanse can be
## aimed at yourself (your card in the top bar, or the use-on-yourself button). Headless:
##   Godot_console.exe --headless --path . -s res://tests/pick_check.gd

var table: Node
var frames := 0
var failures := 0


func _initialize() -> void:
	table = load("res://main.tscn").instantiate()
	table.auto_pick = "random"  # skip the character screen
	root.add_child(table)


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	var g: GameController = table.game
	g.autoplay = false
	g._opening = 0.0
	var tv: TavernView = table.tavern
	check(tv.seat_at(Vector2(480, 470)) == -1, "clicking the table edge picks no bot")
	for seat in range(1, 4):
		var c: Character3D = tv._characters[seat]
		var body := tv._camera.unproject_position(c.global_position + Vector3(0, 1.0 * TavernView.CHARACTER_SCALE, 0)) \
			* float(tv.stretch_shrink)
		check(tv.seat_at(body) == seat, "bot %d found under its own body" % seat)
		# a real click while targeting
		var me := g.players[0]
		g.turn_index = g.order.find(0)
		g.step = GameController.Step.PHASE2
		g._pause = 0.0
		g._hold = 0.0  # the previous bot's attack animation
		g.pending_attack = {}
		me.statuses.clear()
		me.hand.assign([CardDB.get_card("attack")])
		var t := g.players[seat]
		t.statuses.clear()
		t.hand.clear()
		t.hp = PlayerData.MAX_HP
		table._on_card_pressed(0)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = body
		table._gui_input(click)
		check(t.hp == PlayerData.MAX_HP - 1 and me.hand.is_empty(), "clicking bot %d attacks it" % seat)
	# a cleanse on yourself: click your own card in the top bar (a real click through the GUI)
	var you := g.players[0]
	g._hold = 0.0
	g.pending_attack = {}
	g.turn_index = g.order.find(0)
	g.step = GameController.Step.PHASE1
	you.statuses = {"blind": 2}
	you.hand.assign([CardDB.get_card("cleanse_1")])
	table._on_card_pressed(0)
	check(table.self_target_button.visible, "a cleanse shows the use-on-yourself button")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	table.seats[0]._gui_input(press)
	check(not you.has("blind") and you.hand.is_empty(), "clicking your own card cleanses you")
	you.statuses = {"blind": 2}
	you.hand.assign([CardDB.get_card("cleanse_1")])
	table._on_card_pressed(0)
	table.self_target_button.pressed.emit()
	check(not you.has("blind") and not table.self_target_button.visible, "the use-on-yourself button cleanses you")
	you.hand.assign([CardDB.get_card("attack")])
	g.step = GameController.Step.PHASE2
	table._on_card_pressed(0)
	check(not table.self_target_button.visible, "an Attack card doesn't offer yourself")
	table._cancel_targeting()
	print("PICK %s (%d failed)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
	return true
