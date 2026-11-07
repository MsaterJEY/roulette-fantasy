extends SceneTree
## Online play over ENet on this machine: run two copies at once, with RF_NET=enet set,
##   -- host    and    -- guest
## The host opens a 3-seat room, the guest joins and both play their own turns (attacks when
## they can, blocks, minigame passes); then the guest leaves and a bot takes over its seat
## (add `forfeit` on both sides: the guest leaves on purpose and loses at once instead).
## Each prints NETCHECK OK or NETCHECK FAIL with the reasons.

const RUN_SECONDS := 70.0  # real seconds of play (the game runs at Engine.time_scale)
const FORFEIT_AT := 30.0  # with `forfeit`: early, while the guest is still in the game

var args := OS.get_cmdline_user_args()
var host := "host" in args
var net: NetPlay
var started := false
var t := 0.0
var act_wait := 0.0
var leave_at := 0.0  # guest with `forfeit`: when the word has gone out
var fails: Array[String] = []
var seen := {"my_turns": 0, "my_plays": 0, "rounds": 1, "hidden_ok": true, "others_draw_lines": 0, "dropped": false, "logs": 0}


func _initialize() -> void:
	Engine.time_scale = 3.0
	GameConfig.player_name = "Host" if host else "Guest"
	GameConfig.players = 3
	GameConfig.turn_seconds = 8
	GameConfig.rings_to_win = 3
	GameConfig.minigames = true
	GameConfig.start_mode = "host"


## On the first frame: the root is in the tree by then (multiplayer needs it).
func _open() -> void:
	net = NetPlay.node()
	net.failed.connect(func(why: String) -> void: print("net failed: ", why))
	if host:
		net.create_room("demon_hunter" if CharacterDB.ids().has("demon_hunter") else CharacterDB.ids()[0],
			func(err: String) -> void: print("room: ", err if err != "" else "open"))
	else:
		_join_later()


func _join_later() -> void:
	await create_timer(1.0).timeout
	net.join("000000")


func _process(delta: float) -> bool:
	if net == null:
		_open()
		return false
	t += delta
	if not started:
		_lobby_step()
		return t > 30.0 and _fail_now("never started")
	var table := current_scene
	if table == null or not "game" in table:
		return false
	var g: GameController = table.game
	if g.players.is_empty():
		return false
	if not g.log_added.is_connected(_on_log):
		g.log_added.connect(_on_log)
	seen["rounds"] = maxi(seen["rounds"], g.round_no)
	if not host:
		for i in range(1, g.players.size()):
			for c in g.players[i].hand:
				if c["id"] != "hidden":
					seen["hidden_ok"] = false
	_play(g, delta)
	if host and seen["dropped"] and t > RUN_SECONDS + 25.0:
		return _report(g)
	if not host and t > (FORFEIT_AT if "forfeit" in args else RUN_SECONDS):
		if "forfeit" in args and leave_at == 0.0:
			net.forfeit()
			leave_at = t + NetPlay.FORFEIT_SECONDS + 0.2
		if t >= leave_at:
			_report(g)
			net.leave()
			return true
	if host and t > RUN_SECONDS + 40.0:
		return _report(g)
	return false


func _lobby_step() -> void:
	if host and net.seats.size() == 3 and net.seats[1]["human"]:
		if not net.seats[0]["ready"]:
			net.set_ready(0, true)
		if net.all_ready():
			started = true
			net.start()
			change_scene_to_file("res://main.tscn")
	if not host and net.is_guest() and not net.seats.is_empty():
		var me: Dictionary = net.seats[net.my_seat]
		if not me["ready"] and act_wait <= 0.0:
			net.set_ready(net.my_seat, true)
			act_wait = 1.0
		act_wait -= 0.016
		if net.in_game:
			started = true


## Your own turns: attack when you can, else move on; block every attack; pass minigames.
func _play(g: GameController, delta: float) -> void:
	act_wait -= delta
	if act_wait > 0.0 or g.finished:
		return
	if not g.pending_attack.is_empty() and int(g.pending_attack["target"]) == 0:
		g.respond_defense(true)
		act_wait = 0.5
		return
	if g.minigame != null and not g.minigame.done() and g.minigame.current_seat() == 0:
		g.minigame_answer(g.players[0], "")
		act_wait = 0.5
		return
	if not g.is_my_turn() or g.is_held() or g.in_opening() or g.minigame != null or not g.pending_attack.is_empty():
		return
	var me := g.players[0]
	if g.step == GameController.Step.PHASE2:
		var i := me.find_card("attack")
		if i >= 0 and g.can_play(me, me.hand[i]) == "":
			var targets := g.valid_targets(me, me.hand[i])
			if not targets.is_empty():
				seen["my_plays"] += 1
				g.play_card(me, i, targets[0])
				act_wait = 0.6
				return
	if g.step == GameController.Step.ROLL:
		seen["my_turns"] += 1
	g.advance()
	act_wait = 0.6


func _on_log(line: String) -> void:
	seen["logs"] += 1
	if line.contains("จั่วการ์ด") and line.contains("ใบ"):
		seen["others_draw_lines"] += 1
	if line.contains("หลุดจากเกม") or line.contains("ออกจากเกม"):
		seen["dropped"] = true


func _fail_now(why: String) -> bool:
	fails.append(why)
	print("NETCHECK FAIL (%s): %s" % ["host" if host else "guest", why])
	return true


func _report(g: GameController) -> bool:
	if seen["my_turns"] < 2:
		fails.append("only %d of my turns" % seen["my_turns"])
	if seen["rounds"] < (2 if "forfeit" in args else 3):  # `forfeit` stops early
		fails.append("only reached round %d" % seen["rounds"])
	if seen["logs"] < 10:
		fails.append("few log lines (%d)" % seen["logs"])
	if not host:
		if not seen["hidden_ok"]:
			fails.append("saw another player's cards")
		if seen["others_draw_lines"] == 0:
			fails.append("no 'X drew N cards' lines")
		if g.players[0].display_name != "Guest":
			fails.append("seat 0 is %s, not me" % g.players[0].display_name)
	elif not seen["dropped"]:
		fails.append("guest leaving was not noticed")
	elif "forfeit" in args and g.players[1].alive:
		fails.append("guest left but was not out")
	print("seen: ", seen, " alive: ", g.players.map(func(p: PlayerData) -> bool: return p.alive), " finished: ", g.finished)
	print("NETCHECK %s (%s)%s" % ["OK" if fails.is_empty() else "FAIL", "host" if host else "guest",
		"" if fails.is_empty() else ": " + "; ".join(fails)])
	return true
