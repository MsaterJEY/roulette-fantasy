extends SceneTree
## Plays whole bot games on the real table with 2-6 players (headless, fast) and checks each
## one ends with a winner. Run: Godot_console.exe --headless --path . -s res://tests/seats_check.gd
## User arg: player counts to try (default 5 6). Environment NORINGS=1: rings and minigames off.

const MAX_FRAMES := 60000

var counts: Array = []
var table: Node
var frames := 0
var failed := 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		counts.append(int(a))
	if counts.is_empty():
		counts = [5, 6]
	_next()


func _next() -> void:
	if table:
		table.queue_free()
		table = null
	if counts.is_empty():
		return
	GameConfig.players = counts.pop_front()
	GameConfig.rings_to_win = 0 if OS.get_environment("NORINGS") != "" else 5  # NORINGS=1: last one standing only
	GameConfig.minigames = OS.get_environment("NORINGS") == ""
	GameConfig.characters.clear()
	frames = 0
	table = load("res://main.tscn").instantiate()
	root.add_child(table)


func _process(_delta: float) -> bool:
	if table == null:
		print("SEATS %s (%d failed)" % ["OK" if failed == 0 else "FAIL", failed])
		return true
	frames += 1
	var g: GameController = table.game
	if g.finished or frames > MAX_FRAMES:
		var n := g.players.size()
		var ok: bool = g.finished and n == GameConfig.players and table.seats.size() == n
		if not ok:
			failed += 1
		var w := g.players.filter(func(p: PlayerData) -> bool: return p.alive).size()
		print("%d players: %s, round %d, %d alive, %s" % [n, "finished" if g.finished else "NOT finished",
			g.round_no, w, g.win_reason])
		_next()
	return false
