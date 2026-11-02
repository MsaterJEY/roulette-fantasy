extends SceneTree
## Balance check: plays many bot-only games as fast as possible (no UI, no waiting) and
## prints averages: rounds, game minutes, how games end, eliminations, damage taken.
## Headless:
##   Godot_console.exe --headless --path . -s res://tests/balance_sim.gd -- 200 [players] [norings]
## Minutes are estimated from the rule timers with a human-like pace (HUMAN_TURN_SECONDS
## per turn instead of the bots' quick clicks) plus each minigame's answer time.

const STEP := 0.25  # simulated seconds per tick
const MAX_ROUNDS := 60
const HUMAN_TURN_SECONDS := 25.0  # roll + shop + combat for a real player
const MINIGAME_SECONDS := 3 * 4 * 8.0 + 5.0  # 3 rounds × 4 players × ~8 s + results


class Stats:
	extends GameController
	var hits := 0
	var blocks := 0
	var turns := 0
	var unarmed := 0  # attacks on a target holding no Defense card
	var buys := {}  # card id -> times bought

	func _start_attack(a: PlayerData, t: PlayerData) -> void:
		if t.find_card("defense") < 0:
			unarmed += 1
		super(a, t)

	func buy(p: PlayerData, slot: int, replace_index: int = -1) -> bool:
		var id: String = shop[slot].get("id", "") if slot >= 0 and slot < shop.size() else ""
		var ok := super(p, slot, replace_index)
		if ok:
			buys[id] = buys.get(id, 0) + 1
		return ok

	func _resolve_attack(a: PlayerData, t: PlayerData, defended: bool) -> void:
		if defended:
			blocks += 1
		else:
			hits += 1
		super(a, t, defended)

	func _log(_text: String) -> void:
		pass  # quiet: thousands of games

	func _end_turn() -> void:
		turns += 1
		super()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if not args.is_empty() else 100
	var sim_players := int(args[1]) if args.size() > 1 else 4  # 2-6
	var no_rings := "norings" in args
	var rounds := 0.0
	var minutes := 0.0
	var by_rings := 0
	var by_survival := 0
	var timeout := 0
	var elims := 0
	var games_with_elim := 0
	var hits := 0
	var blocks := 0
	var round_hist := {}
	var unarmed := 0
	var buys := {}
	for i in games:
		var g := Stats.new()
		g.autoplay = true
		root.add_child(g)
		var names: Array = ["คุณ"]
		for k in range(1, sim_players):
			names.append("บอท %d" % k)
		g.start_game(names)
		if no_rings:  # the "ไม่ใช้แหวน" room: minigames and rings off, last one standing wins
			g.rings_to_win = 0
			g.minigames_enabled = false
		while not g.finished and g.round_no <= MAX_ROUNDS:
			g._process(STEP)
		var dead := g.players.filter(func(p: PlayerData) -> bool: return not p.alive).size()
		elims += dead
		games_with_elim += 1 if dead > 0 else 0
		if not g.finished:
			timeout += 1
		elif g.win_reason.begins_with("สะสม"):
			by_rings += 1
		else:
			by_survival += 1
		rounds += g.round_no
		minutes += (g.turns * HUMAN_TURN_SECONDS + g.minigames_played * MINIGAME_SECONDS) / 60.0
		hits += g.hits
		blocks += g.blocks
		unarmed += g.unarmed
		for id: String in g.buys:
			buys[id] = buys.get(id, 0) + g.buys[id]
		var bucket := int(g.round_no / 5) * 5
		round_hist[bucket] = round_hist.get(bucket, 0) + 1
		g.free()
	var n := float(games)
	print("BALANCE games %d" % games)
	print("  rounds avg %.1f   est. minutes avg %.1f" % [rounds / n, minutes / n])
	print("  end: rings %d%%  last alive %d%%  no winner by round %d %d%%" % [
		100 * by_rings / games, 100 * by_survival / games, MAX_ROUNDS, 100 * timeout / games])
	print("  eliminations per game %.2f   games with an elimination %d%%" % [elims / n, 100 * games_with_elim / games])
	print("  attacks per game %.1f   blocked %d%%" % [(hits + blocks) / n, 100 * blocks / maxi(1, hits + blocks)])
	print("  target had no Defense card: %d%% of attacks" % (100 * unarmed / maxi(1, hits + blocks)))
	var bought := PackedStringArray()
	for id: String in buys:
		bought.append("%s %.1f" % [id, buys[id] / n])
	print("  bought per game: " + ", ".join(bought))
	var keys := round_hist.keys()
	keys.sort()
	var hist := PackedStringArray()
	for k: int in keys:
		hist.append("%d-%d: %d" % [k, k + 4, round_hist[k]])
	print("  game length (rounds): " + ", ".join(hist))
	quit()
