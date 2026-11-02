extends SceneTree
## Screenshot helper: the table with 2-6 seats (user arg, default 3), as the lobby would
## start it. Add `result` for the end screen with that many players, `norings` for a room
## with rings and minigames off, `lastkill` (with 2 players) for you knocking out the last bot, `youdie` for the last bot
## knocking you out (add `decline`: you had a Defense card and chose not to block), `spectate` (3 players) for the last blow between bots after you're out, `sdlabel`
## for the rounds-left plate on its last round. Run with --write-movie.

var frames := 0
var table: Node
var args := OS.get_cmdline_user_args()


func _initialize() -> void:
	GameConfig.players = int(args[0]) if args.size() > 0 else 3
	GameConfig.rings_to_win = 0 if "norings" in args else 3
	GameConfig.minigames = not "norings" in args
	GameConfig.fill_seats(CharacterDB.ids().pick_random())
	table = load("res://main.tscn").instantiate()
	root.add_child(table)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5 and "result" in args:
		var g: GameController = table.game
		g._opening = 0.0
		g.players[1].rings = 3
		g.players[1].kills = 2
		g.players[0].damage = 2
		for i in range(2, g.players.size(), 2):
			g.players[i].alive = false
			g.players[i].hp = 0
		g.round_no = 11
		g._finish(g.players[1], "สะสมแหวนครบ 3 วง")
	if frames == 5 and "lastkill" in args:  # you knock out the last bot: the game ends on that finisher
		var g: GameController = table.game
		g._opening = 0.0
		g.turn_index = g.order.find(0)
		g._pause = 0.0
		g.step = GameController.Step.PHASE2
		for i in range(1, g.players.size()):
			g.players[i].hp = 1
			g.players[i].hand.clear()
		g.players[0].hand.assign([CardDB.get_card("attack")])
		g.state_changed.emit()
		g.play_card(g.players[0], 0, 1)
	if frames == 5 and "youdie" in args:  # the last bot knocks you out: the game ends on your finisher
		var g: GameController = table.game
		g._opening = 0.0
		var bot := g.players[1]
		g.turn_index = g.order.find(1)
		g._pause = 0.0
		g.step = GameController.Step.PHASE2
		g.players[0].hp = 1
		g.players[0].hand.clear()
		if "decline" in args:  # you hold a Defense card but choose not to block
			g.players[0].hand.append(CardDB.get_card("defense"))
		g._start_attack(bot, g.players[0])
		if "decline" in args:
			g.respond_defense(false)
	if frames == 5 and "spectate" in args:  # you're out (bots on fast-forward); bot 1 knocks out the last other bot
		var g: GameController = table.game
		g._opening = 0.0
		g._eliminate(g.players[0], g.players[1])
		g.turn_index = g.order.find(1)
		g._pause = 0.0
		g.step = GameController.Step.PHASE2
		for i in range(2, g.players.size()):
			g.players[i].hp = 1
			g.players[i].hand.clear()
		g._start_attack(g.players[1], g.players[2])
	if frames == 5 and "sdlabel" in args:  # one round left before max HP and the hand limit drop
		var g: GameController = table.game
		g.shrink_in = 1
		g.state_changed.emit()
	return frames > (420 if "lastkill" in args or "youdie" in args or "spectate" in args else 300)
