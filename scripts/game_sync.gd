class_name GameSync
extends RefCounted
## Online play: the host's game as one guest may see it, and back into that guest's mirror
## (GameController.remote). The table is turned for each guest so that they sit at seat 0,
## as you always do on your own screen: host seat s is guest seat (s - viewer) mod n. Other
## players' hands travel as face-down cards (HIDDEN), and what they drew or bought is not
## named. A spectator (viewer WATCHER) gets an extra, empty seat 0 of their own, out of the
## game, and every player one place on: to the table they're just someone knocked out.

const WATCHER := -1
const HIDDEN := {"id": "hidden", "name": "?", "type": "hidden", "phase": "passive", "target": "none",
	"price": 0, "desc": ""}

## Signals sent to guests, and which of their arguments are seats.
const EVENT_SEATS := {
	"rolled": [0],
	"attack_incoming": [0, 1],
	"game_over": [0],
	"bought": [0],
	"turn_started": [0],
	"card_played": [0, 1],
	"attacked": [0, 1],
	"showdown_shrunk": [],
	"minigame_started": [],
	"minigame_changed": [],
	"minigame_finished": [],
}


static func to_view(seat: int, viewer: int, n: int) -> int:
	if viewer == WATCHER:
		return seat if seat < 0 else seat + 1
	return seat if seat < 0 else posmod(seat - viewer, n)


static func from_view(seat: int, viewer: int, n: int) -> int:
	if viewer == WATCHER:
		return seat
	return seat if seat < 0 else posmod(seat + viewer, n)


## The host's game `g` as seen from host seat `viewer`.
static func snapshot(g: GameController, viewer: int) -> Dictionary:
	var n := g.players.size()
	var players: Array = []
	for i in n:
		var p := g.players[from_view(i, viewer, n)]
		var hand: Array = p.hand.duplicate() if p.seat == viewer else []
		if p.seat != viewer:
			for c in p.hand:
				hand.append(HIDDEN)
		players.append({"name": p.display_name, "bot": p.is_bot, "character": p.character, "hp": p.hp,
			"gold": p.gold, "shards": p.shards, "rings": p.rings, "hand": hand, "alive": p.alive,
			"kills": p.kills, "damage": p.damage, "helps": p.helps, "statuses": p.statuses.duplicate()})
	if viewer == WATCHER:
		players.push_front({"name": "ผู้ชม", "bot": false, "character": "", "hp": 0, "gold": 0, "shards": 0,
			"rings": 0, "hand": [], "alive": false, "kills": 0, "damage": 0, "helps": 0, "statuses": {}})
	var pending := {}
	if not g.pending_attack.is_empty():
		pending = {"attacker": to_view(g.pending_attack["attacker"], viewer, n),
			"target": to_view(g.pending_attack["target"], viewer, n), "time": g.pending_attack["time"]}
	var rolls: Array = []
	for r in g.opening_rolls:
		rolls.append({"seat": to_view(r["seat"], viewer, n), "dice": r["dice"], "totals": r["totals"]})
	var mg = null
	if g.minigame != null:
		var m := g.minigame
		var scores := {}
		for s: int in m.scores:
			scores[to_view(s, viewer, n)] = m.scores[s]
		var answers: Array = []
		for a in m.answers:
			var e: Dictionary = a.duplicate()
			e["seat"] = to_view(a["seat"], viewer, n)
			answers.append(e)
		mg = {"question": m.question, "seats": m.seats.map(func(s: int) -> int: return to_view(s, viewer, n)),
			"round": m.round_no, "turn": m.turn, "time": m.time_left, "answers": answers, "scores": scores,
			"used": m.used}
	return {
		"players": players, "watching": viewer == WATCHER,
		"order": g.order.map(func(s: int) -> int: return to_view(s, viewer, n)),
		"round": g.round_no, "turn": g.turn_index, "step": g.step, "step_seconds": g.step_seconds,
		"time": g.time_left, "speed": g.speed, "finished": g.finished, "rings_to_win": g.rings_to_win,
		"minigames": g.minigames_enabled, "max_hp": g.max_hp, "hand_limit": g.hand_limit,
		"shrink_in": g.shrink_in, "win_reason": g.win_reason, "pending": pending, "shop": g.shop,
		"minigames_played": g.minigames_played, "held": g._hold > 0.0, "pause": g._pause,
		"opening": g._opening, "rolls": rolls, "pre_roll": g._pre_roll_items, "minigame": mg,
		"minigame_close": g._minigame_close,
	}


## Put snapshot `d` into the mirror `g`. The PlayerData objects are kept (the table holds them).
static func apply(g: GameController, d: Dictionary) -> void:
	var list: Array = d["players"]
	if g.players.size() != list.size():
		g.players.clear()
		for i in list.size():
			g.players.append(PlayerData.new(i, list[i]["name"], list[i]["bot"]))
	for i in list.size():
		var p := g.players[i]
		var e: Dictionary = list[i]
		p.display_name = e["name"]
		p.is_bot = e["bot"] if i != 0 else false  # seat 0 is you
		p.character = e["character"]
		p.hp = e["hp"]
		p.gold = e["gold"]
		p.shards = e["shards"]
		p.rings = e["rings"]
		p.hand.assign(e["hand"])
		p.alive = e["alive"]
		p.kills = e["kills"]
		p.damage = e["damage"]
		p.helps = e["helps"]
		p.statuses = e["statuses"]
	g.watching = d["watching"]
	g.order.assign(d["order"])
	g.round_no = d["round"]
	g.turn_index = d["turn"]
	g.step = d["step"]
	g.step_seconds = d["step_seconds"]
	g.time_left = d["time"]
	g.speed = d["speed"]
	g.finished = d["finished"]
	g.rings_to_win = d["rings_to_win"]
	g.minigames_enabled = d["minigames"]
	g.max_hp = d["max_hp"]
	g.hand_limit = d["hand_limit"]
	g.shrink_in = d["shrink_in"]
	g.win_reason = d["win_reason"]
	g.pending_attack = d["pending"]
	g.shop.assign(d["shop"])
	g.minigames_played = d["minigames_played"]
	g.remote_held = d["held"]
	g._pause = d["pause"]
	g._opening = d["opening"]
	g._pre_roll_items = d["pre_roll"]
	g._minigame_close = d["minigame_close"]
	g.opening_rolls.clear()
	for r: Dictionary in d["rolls"]:
		var dice: Array[int] = []
		dice.assign(r["dice"])
		g.opening_rolls.append({"seat": r["seat"], "dice": dice, "totals": r["totals"]})
	var mg = d["minigame"]
	if mg == null:
		g.minigame = null
	else:
		var seats: Array[int] = []
		seats.assign(mg["seats"])
		if g.minigame == null or g.minigame.question != mg["question"]:
			g.minigame = Minigame.new(mg["question"], seats)
		var m := g.minigame
		m.seats = seats
		m.round_no = mg["round"]
		m.turn = mg["turn"]
		m.time_left = mg["time"]
		m.answers.assign(mg["answers"])
		m.scores = mg["scores"]
		m.used = mg["used"]


## Signal `name`'s arguments as host seat `viewer` gets them: seats turned, private cards hidden.
static func event_args(name: String, args: Array, viewer: int, n: int) -> Array:
	var out := args.duplicate(true)
	for i: int in EVENT_SEATS.get(name, []):
		out[i] = to_view(out[i], viewer, n)
	match name:
		"rolled":  # [seat, dice, gold, drawn, unlucky]: the cards drawn are theirs to know
			if args[0] != viewer:
				out[3] = (args[3] as Array).map(func(_c: String) -> String: return "?")
		"bought":  # [seat, card]
			if args[0] != viewer:
				out[1] = HIDDEN
		"minigame_finished":  # [results]
			for r: Dictionary in out[0]:
				r["seat"] = to_view(r["seat"], viewer, n)
	return out


## Emit a received event on the mirror, with the typed arrays its listeners expect.
static func emit_event(g: GameController, name: String, a: Array) -> void:
	match name:
		"rolled":
			var dice: Array[int] = []
			dice.assign(a[1])
			var drawn: Array[String] = []
			drawn.assign(a[3])
			g.rolled.emit(a[0], dice, a[2], drawn, a[4])
		"attack_incoming":
			g.attack_incoming.emit(a[0], a[1])
		"game_over":
			g.game_over.emit(a[0])
		"bought":
			g.bought.emit(a[0], a[1])
		"turn_started":
			g.turn_started.emit(a[0])
		"card_played":
			g.card_played.emit(a[0], a[1], a[2])
		"attacked":
			g.attacked.emit(a[0], a[1], a[2])
		"showdown_shrunk":
			g.showdown_shrunk.emit()
		"minigame_started":
			g.minigame_started.emit()
		"minigame_changed":
			g.minigame_changed.emit()
		"minigame_finished":
			var results: Array[Dictionary] = []
			results.assign(a[0])
			g.minigame_finished.emit(results)
