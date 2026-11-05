extends SceneTree
## Online spectator over ENet on this machine: run with RF_NET=enet alongside net_check.gd's
## `-- host` and `-- guest`. Joins the game in progress, watches it, and prints WATCHCHECK OK or
## WATCHCHECK FAIL with the reasons. With `-- long` it stays on, to see the host leave.

const JOIN_AT := 12.0  # the game is well under way by then
const WATCH_SECONDS := 25.0

var net: NetPlay
var t := 0.0
var asked := false
var began := 0.0
var first_round := 0
var events := 0
var logs := 0
var fails: Array[String] = []


func _initialize() -> void:
	Engine.time_scale = 3.0
	GameConfig.player_name = "Watcher"


func _process(delta: float) -> bool:
	if net == null:
		net = NetPlay.node()
		net.failed.connect(func(why: String) -> void: fails.append("failed: " + why))
		return false
	t += delta
	if not asked and t > JOIN_AT:
		asked = true
		net.join("000000", "", true)
	var table := current_scene
	if table == null or not "game" in table or table.game.players.is_empty():
		return t > JOIN_AT + 30.0 and _report(null)
	var g: GameController = table.game
	if began == 0.0:
		began = t
		first_round = g.round_no
		g.log_added.connect(func(_l: String) -> void: logs += 1)
		g.attacked.connect(func(_a: int, target: int, _b: bool) -> void:
			events += 1
			if target == 0:
				fails.append("attacked the spectator's place"))
	for i in g.players.size():
		for c in g.players[i].hand:
			if c["id"] != "hidden":
				fails.append("saw a card in seat %d" % i)
	if g.is_my_turn():
		fails.append("it was the spectator's turn")
	return t - began > WATCH_SECONDS * (20.0 if "long" in OS.get_cmdline_user_args() else 1.0) and _report(g)


func _report(g: GameController) -> bool:
	if g == null:
		fails.append("the table never opened")
	else:
		if not g.watching:
			fails.append("not watching")
		if g.players.size() != 4:
			fails.append("%d places, not 3 players + spectator" % g.players.size())
		if g.players[0].alive or not g.players[0].hand.is_empty():
			fails.append("the spectator's place is in the game")
		if g.round_no <= first_round:
			fails.append("the game didn't move (round %d)" % g.round_no)
		if logs == 0:
			fails.append("no log lines")
		if current_scene.seats[0].visible:
			fails.append("the spectator has a player card")
	print("watched rounds %d..%d, %d attacks, %d log lines" % [first_round, g.round_no if g else 0, events, logs])
	print("WATCHCHECK %s" % ("OK" if fails.is_empty() else "FAIL: " + "; ".join(fails.slice(0, 5))))
	net.leave()
	return true
