class_name GameController
extends Node
## Rules and turn flow, no UI. Each player's turn: Roll → Preparation → Combat
## (code names: Step.PHASE1 / Step.PHASE2).
## The table listens to the signals and calls roll_dice() / advance() / play_card() /
## respond_defense() for the human player; bots go through BotBrain.

signal log_added(bbcode: String)
## Every log line, for online play: `owner` (a seat) sees `text`, everyone else `others` ("" =
## nothing); owner -1 = everyone sees `text`. log_added carries what seat 0 (you) sees.
signal log_entry(owner: int, text: String, others: String)
signal state_changed
## drawn = names of the cards drawn after the roll; unlucky = bad luck lowered the result
signal rolled(seat: int, dice: Array[int], gold: int, drawn: Array[String], unlucky: bool)
signal attack_incoming(attacker: int, target: int)
signal game_over(winner: int)
signal bought(seat: int, card: Dictionary)
signal turn_started(seat: int)
## Max HP and the hand limit just dropped (every SHRINK_ROUNDS rounds).
signal showdown_shrunk
## The opening roll that set the turn order: one entry per seat, {"seat", "dice" (first
## throw), "totals" (first total, then any tie-break totals)}; `order` is already set.
signal order_rolled(rolls: Array[Dictionary])
## A card left `seat`'s hand towards `target` (the same seat for self cards), just before its
## effect is applied: the table throws it across the room.
signal card_played(seat: int, target: int, card: Dictionary)
## An attack landed on `target`: blocked = a Defense card stopped it, otherwise 1 HP was lost.
signal attacked(attacker: int, target: int, blocked: bool)
## Minigame flow: started, an answer came in, finished (results from Minigame.results()).
signal minigame_started
signal minigame_changed
signal minigame_finished(results: Array[Dictionary])

enum Step { ROLL, PHASE1, PHASE2 }

const STEP_NAMES := {
	Step.ROLL: "Roll · ทอยลูกเต๋า",
	Step.PHASE1: "Preparation · เตรียมตัว",
	Step.PHASE2: "Combat · ต่อสู้",
}
const STEP_SECONDS := 20.0
const DEFENSE_SECONDS := 10.0
const DRAW_PER_TURN := 2
const HAND_LIMIT := 7
const MINIGAME_EVERY := 2
## Passive card: lifts a No Items curse by itself the moment it lands (or when you get the
## card while cursed). A player may hold only one.
const WARD := "ward_no_items"
## Shrinking table (ช่วงชี้ขาด), so games can't drag on (most attacks get blocked; without
## rings only knockouts end a game): every SHRINK_ROUNDS finished rounds everyone's max HP and
## the hand limit drop by 1 (not below MIN_MAX_HP / MIN_HAND_LIMIT).
const SHRINK_ROUNDS := 5
const MIN_MAX_HP := 1
const MIN_HAND_LIMIT := 3
const MINIGAME_RESULT_SECONDS := 5.0  # results stay up this long before play goes on
const SPECTATE_SPEED := 3.0  # once you are out, the bots play on faster
const ROLL_SECONDS := 1.2
## Opening: each player's throw is shown one after another, then the order, then turn 1.
const OPENING_WAIT_SECONDS := 3.0  # a breather after the game opens, before the first throw
const OPENING_THROW_SECONDS := 1.4
const OPENING_SHOW_SECONDS := 2.0
const MAX_PRE_ROLL_ITEMS := 2
const MAX_ROLL_GOLD := 9  # 3 dice: 18 / 2
const SHOP_SLOTS := 5
## Defense cards always on offer each restock (the rest is random), so players can buy protection.
const SHOP_DEFENSES := 2
const SHARDS_PER_RING := 2  # balance sim: 3 made games ~30 min
const CURSES := ["no_items", "no_shop", "bad_luck", "blind"]
const STATUS_NAMES := {
	"no_items": "ห้ามใช้ไอเทม", "no_shop": "ห้ามซื้อของ", "bad_luck": "ดวงซวย",
	"blind": "ตาบอด", "truce": "สงบศึก", "free_block": "ป้องกันฟรี",
}
## Effects that last until used rather than for a number of turns. For free_block the value
## is the number of free blocks left; for bad_luck it is unused.
const UNTIL_USED := ["bad_luck", "free_block"]
## Good effects (shown in blue); everything else in STATUS_NAMES is a curse.
const BUFFS := ["truce", "free_block"]
const CURSE_TURNS := {"no_items": 1, "no_shop": 2, "bad_luck": 1, "blind": 2, "truce": 2}

var players: Array[PlayerData] = []
var order: Array[int] = []  # seat numbers in turn order
var deck: Array[Dictionary] = []
var discard: Array[Dictionary] = []
var round_no := 1
var turn_index := 0
var step: Step = Step.ROLL
var step_seconds := STEP_SECONDS  # per phase; the room setting (GameConfig.turn_seconds)
var time_left := STEP_SECONDS
var autoplay := false  # the human seat is played by the bot logic (tests)
var speed := 1.0
var rng := RandomNumberGenerator.new()
var finished := false
var rings_to_win := PlayerData.RINGS_TO_WIN  # the room setting (GameConfig); 0 = rings off: win by knocking everyone out
var minigames_enabled := true  # the room setting: a minigame every MINIGAME_EVERY rounds
var max_hp := PlayerData.MAX_HP  # lowered every SHRINK_ROUNDS rounds
var hand_limit := HAND_LIMIT  # lowered every SHRINK_ROUNDS rounds
var shrink_in := SHRINK_ROUNDS  # rounds left until max HP and the hand limit drop
var win_reason := ""  # e.g. "สะสมแหวนครบ 5 วง", set when the game ends
## {"attacker": seat, "target": seat, "time": seconds} while a human decides to defend
var pending_attack: Dictionary = {}
## Shop offers for this round; an empty dict is a sold-out slot.
var shop: Array[Dictionary] = []
var minigames_played := 0
## The minigame in progress (turns are paused while it runs), or null.
var minigame: Minigame = null

var _bot_wait := 0.0
var _bot_actions := 0  # actions a bot took in the current step (safety cap)
var _pause := 0.0  # dice animation in progress
var _pre_roll_items := 0
var _opening := 0.0  # seconds left of the opening roll-off before the first turn
var _hold := 0.0  # real seconds the game waits for an animation (an attack, a finisher)
var opening_rolls: Array[Dictionary] = []
var _minigame_close := 0.0  # seconds the results stay up
var _question_bag: Array[int] = []  # question indexes not asked yet this game
## Online guest: this game only mirrors the host's (GameSync.apply). Its clocks run on between
## updates, nothing else happens here, and your actions go to the host through `remote`
## (name, args) instead of being applied.
var remote := Callable()
var remote_held := false  # the host is waiting for an animation


## `characters[seat]`: each seat's character id (optional; tests play without). `humans[seat]`:
## seats played by people (online); without it, seat 0 (you) only.
func start_game(names: Array, characters: Array = [], humans: Array = []) -> void:
	rng.randomize()
	players.clear()
	for i in names.size():
		var human: bool = humans[i] if i < humans.size() else i == 0
		players.append(PlayerData.new(i, names[i], not human))
		if i < characters.size():
			players[i].character = characters[i]
	deck = CardDB.make_deck(rng)
	discard.clear()
	for p in players:
		_draw(p, 1, false)  # the starting item card
	_roll_for_order()
	round_no = 1
	turn_index = 0
	finished = false
	max_hp = PlayerData.MAX_HP
	hand_limit = HAND_LIMIT
	shrink_in = SHRINK_ROUNDS
	pending_attack = {}
	minigames_played = 0
	minigame = null
	_question_bag.clear()
	restock_shop()
	var names_in_order := order.map(func(s: int) -> String: return players[s].display_name)
	_log("ลำดับการเล่น (แต้มมากไปน้อย): " + " → ".join(PackedStringArray(names_in_order)))
	_opening = OPENING_WAIT_SECONDS + players.size() * OPENING_THROW_SECONDS + OPENING_SHOW_SECONDS
	order_rolled.emit(opening_rolls)
	state_changed.emit()


## Everyone throws 3 dice; the highest total plays first, the lowest last. Players who tie
## throw again among themselves (as often as needed) to settle their places.
func _roll_for_order() -> void:
	opening_rolls.clear()
	var totals := {}  # seat -> [first total, tie-break totals...]
	for p in players:
		var dice: Array[int] = [rng.randi_range(1, 6), rng.randi_range(1, 6), rng.randi_range(1, 6)]
		totals[p.seat] = [dice[0] + dice[1] + dice[2]]
		opening_rolls.append({"seat": p.seat, "dice": dice, "totals": totals[p.seat]})
		_log("%s ทอยลำดับได้ %d + %d + %d = %d" % [p.display_name, dice[0], dice[1], dice[2], totals[p.seat][0]])
	while true:
		var tied := {}  # same results so far -> seats
		for s: int in totals:
			var key := str(totals[s])
			tied[key] = tied.get(key, []) + [s]
		var again := false
		for seats: Array in tied.values():
			if seats.size() < 2:
				continue
			again = true
			for s: int in seats:
				var t := rng.randi_range(1, 6) + rng.randi_range(1, 6) + rng.randi_range(1, 6)
				totals[s].append(t)
				_log("%s ทอยแก้เสมอได้ %d" % [players[s].display_name, t])
		if not again:
			break
	order.assign(range(players.size()))
	# compare the throws in turn: first total, then the tie-breaks
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta: Array = totals[a]
		var tb: Array = totals[b]
		for i in mini(ta.size(), tb.size()):
			if ta[i] != tb[i]:
				return ta[i] > tb[i]
		return a < b)


## Pause the game (timers, bots) for `seconds` of real time while the table plays an
## animation, so nothing happens on top of it.
func hold(seconds: float) -> void:
	_hold = maxf(_hold, seconds)
	state_changed.emit()  # the table hides its buttons meanwhile


func is_held() -> bool:
	return _hold > 0.0 or remote_held


## Seconds left of the wait before the opening throws start (0 once they have).
func opening_wait_left() -> float:
	return maxf(0.0, _opening - players.size() * OPENING_THROW_SECONDS - OPENING_SHOW_SECONDS)


## True while the opening roll-off is still being shown (no turn has started yet).
func in_opening() -> bool:
	return _opening > 0.0


func current() -> PlayerData:
	return players[order[turn_index]]


func is_human(p: PlayerData) -> bool:
	return not p.is_bot and not autoplay


func is_human_turn() -> bool:
	return is_human(current()) and not finished


## `p` is you: seat 0 is always the one at this screen (online guests see the table turned
## so that they sit at seat 0 too).
func is_me(p: PlayerData) -> bool:
	return p.seat == 0 and is_human(p)


func is_my_turn() -> bool:
	return is_me(current()) and not finished


func is_mirror() -> bool:
	return remote.is_valid()


func step_name() -> String:
	return STEP_NAMES[step]


func alive_players() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in players:
		if p.alive:
			out.append(p)
	return out


func _process(delta: float) -> void:
	if players.is_empty() or finished:
		return
	if is_mirror():
		_mirror_tick(delta)
		return
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			state_changed.emit()  # the table brings its buttons back
		return
	var d := delta * speed
	if _opening > 0.0:
		_opening -= d
		if _opening <= 0.0:
			_begin_step(Step.ROLL)
		return
	if minigame != null:
		_minigame_tick(d)
		return
	if not pending_attack.is_empty():
		pending_attack["time"] -= d
		if pending_attack["time"] <= 0.0:
			var t := players[pending_attack["target"]]
			respond_defense(t.find_card("defense") >= 0)
		return
	if _pause > 0.0:
		_pause -= d
		if _pause <= 0.0:
			_begin_step(Step.PHASE1)
		return
	time_left -= d
	if not is_human(current()):
		_bot_wait -= d
		if _bot_wait <= 0.0:
			_bot_act()
	elif time_left <= 0.0:
		_log("หมดเวลา")
		if step == Step.ROLL:
			roll_dice()
		else:
			advance()


## A guest's copy between the host's updates: the clocks the screen shows keep running.
func _mirror_tick(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			state_changed.emit()
	if remote_held:
		return
	var d := delta * speed
	if _opening > 0.0:
		_opening -= d
	elif minigame != null:
		if minigame.done():
			_minigame_close -= d
		else:
			minigame.time_left -= d
	elif not pending_attack.is_empty():
		pending_attack["time"] -= d
	elif _pause > 0.0:
		_pause -= d
	else:
		time_left -= d


# ---------- turn actions ----------

func roll_dice() -> void:
	if is_mirror():
		remote.call("advance", [])
		return
	if step != Step.ROLL or _pause > 0.0 or _hold > 0.0 or finished:
		return
	var p := current()
	var dice: Array[int] = [rng.randi_range(1, 6), rng.randi_range(1, 6), rng.randi_range(1, 6)]
	var total: int = dice[0] + dice[1] + dice[2]
	var gold := maxi(1, total / 2)
	_log("%s ทอยได้ %d + %d + %d = %d" % [p.display_name, dice[0], dice[1], dice[2], total])
	var unlucky := p.has("bad_luck")
	if unlucky:
		gold = 1 if gold == MAX_ROLL_GOLD else maxi(1, gold - 1)
		p.statuses.erase("bad_luck")
		_log("[color=#b27ce0]ดวงซวย! ผลลดลง 1 ระดับ[/color]")
	p.gold += gold
	_log("%s ได้เงิน %d" % [p.display_name, gold])
	var drawn := _draw(p, DRAW_PER_TURN, true)
	rolled.emit(p.seat, dice, gold, drawn, unlucky)
	_pause = ROLL_SECONDS
	state_changed.emit()


func advance() -> void:
	if is_mirror():
		if not is_held():
			remote.call("advance", [])
		return
	if _opening > 0.0 or _pause > 0.0 or _hold > 0.0 or not pending_attack.is_empty() or finished or minigame != null:
		return
	match step:
		Step.ROLL:
			roll_dice()
		Step.PHASE1:
			_begin_step(Step.PHASE2)
		Step.PHASE2:
			_end_turn()


# ---------- cards ----------

## Why `p` cannot play `card` right now, or "" if it can.
func can_play(p: PlayerData, card: Dictionary) -> String:
	if finished or not p.alive:
		return "เล่นไม่ได้แล้ว"
	if card["phase"] == "reaction":
		return "การ์ดนี้ใช้ได้ตอนถูกโจมตีเท่านั้น"
	if card["phase"] == "passive":
		return "การ์ดนี้ทำงานเองเมื่อโดนคำสาปห้ามใช้ไอเทม"
	if _hold > 0.0:
		return "รอให้ท่าโจมตีเล่นจบก่อน"
	if _opening > 0.0:
		return "รอทอยลำดับการเล่นก่อน"
	if minigame != null:
		return "รอ Minigame จบก่อน"
	if p != current():
		return "ยังไม่ถึงเทิร์นของคุณ"
	if _pause > 0.0 or not pending_attack.is_empty():
		return "รอสักครู่"
	if p.has("no_items"):
		return "คุณโดนคำสาป ห้ามใช้ไอเทม"
	if card["phase"] == "p2" and step != Step.PHASE2:
		return "การ์ดนี้ใช้ได้ในช่วง Combat (ต่อสู้)"
	if step == Step.ROLL and _pre_roll_items >= MAX_PRE_ROLL_ITEMS:
		return "ก่อนทอยลูกเต๋า ใช้การ์ดได้สูงสุด %d ใบ" % MAX_PRE_ROLL_ITEMS
	if card["id"] == "attack" and p.has("truce"):
		return "คุณใช้สงบศึกอยู่ โจมตีไม่ได้"
	if card["id"] in ["heal_1", "heal_2"] and p.hp >= max_hp:
		return "เลือดเต็มอยู่แล้ว"
	if card["target"] in ["enemy", "any"] and valid_targets(p, card).is_empty():
		return "ไม่มีเป้าหมายที่เลือกได้"
	return ""


func valid_targets(p: PlayerData, card: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for t in alive_players():
		match card["target"]:
			"enemy":
				if t == p or (card["id"] == "attack" and t.has("truce")):
					continue
				out.append(t.seat)
			"any":
				out.append(t.seat)
	return out


## Play the card at hand_index. Returns false (and logs why) if it is not allowed.
func play_card(p: PlayerData, hand_index: int, target_seat: int = -1) -> bool:
	if hand_index < 0 or hand_index >= p.hand.size():
		return false
	var card := p.hand[hand_index]
	var reason := can_play(p, card)
	if reason == "" and card["target"] in ["enemy", "any"] and not target_seat in valid_targets(p, card):
		reason = "เป้าหมายนี้เลือกไม่ได้"
	if reason != "":
		if is_human(p):
			_log("[color=#ff6b6b]%s[/color]" % reason, p.seat)
		return false
	if is_mirror():
		remote.call("play_card", [hand_index, target_seat])
		return true
	p.hand.remove_at(hand_index)
	discard.append(card)
	if step == Step.ROLL:
		_pre_roll_items += 1
	var t: PlayerData = players[target_seat] if target_seat >= 0 else p
	if card["target"] in ["enemy", "any"]:
		_log("%s ใช้ [b]%s[/b] กับ %s" % [p.display_name, card_name(p, card), t.display_name])
	else:
		_log("%s ใช้ [b]%s[/b]" % [p.display_name, card_name(p, card)])
	card_played.emit(p.seat, t.seat, card)
	if card["type"] == "help":
		p.helps += 1
	_apply(p, t, card["id"])
	state_changed.emit()
	return true


func _apply(p: PlayerData, t: PlayerData, id: String) -> void:
	match id:
		"attack":
			_start_attack(p, t)
		"heal_1", "heal_2":
			var before := p.hp
			p.heal(1 if id == "heal_1" else 2, max_hp)
			_log("%s เลือด %d → %d" % [p.display_name, before, p.hp])
		"gain_defense":
			p.statuses["free_block"] = int(p.statuses.get("free_block", 0)) + 1
			_log("%s ได้ [b]ป้องกันฟรี[/b] (%d ครั้ง)" % [p.display_name, p.statuses["free_block"]])
		"cleanse_1":
			for c in CURSES:
				if t.has(c):
					t.statuses.erase(c)
					_log("ล้างคำสาป %s ของ %s" % [STATUS_NAMES[c], t.display_name])
					break
		"cleanse_all":
			for c in CURSES:
				t.statuses.erase(c)
		"truce":
			p.statuses["truce"] = CURSE_TURNS["truce"]
		"no_items", "no_shop", "bad_luck", "blind":
			if id == "no_items" and t.find_card(WARD) >= 0:
				_use_ward(t)  # lifted before it takes hold
				return
			t.statuses[id] = CURSE_TURNS[id]


## `t` has a No Items curse (or is just getting one) and holds the ward: the ward is used up
## and the curse is gone.
func _use_ward(t: PlayerData) -> void:
	var i := t.find_card(WARD)
	var card := t.hand[i]
	t.hand.remove_at(i)
	discard.append(card)
	t.statuses.erase("no_items")
	t.helps += 1
	_log("[color=#7fd97f]%s ใช้ [b]%s[/b] อัตโนมัติ · ไม่โดนห้ามใช้ไอเทม[/color]" % [t.display_name, card["name"]])
	card_played.emit(t.seat, t.seat, card)


func _ward_check(p: PlayerData) -> void:
	if p.has("no_items") and p.find_card(WARD) >= 0:
		_use_ward(p)


## What `card` is called in `p`'s hands: the Attack card takes the name of the character's
## weapon (same effect); everything else keeps its own name.
func card_name(p: PlayerData, card: Dictionary) -> String:
	if card.get("id") == "attack" and p.character != "":
		return CharacterDB.get_character(p.character).get("weapon", card["name"])
	return card["name"]


## The picture for `card` in `p`'s hands (the weapon icon for a character's Attack card).
func card_icon(p: PlayerData, card: Dictionary) -> String:
	if card.get("id") == "attack" and p.character != "":
		return CharacterDB.get_character(p.character).get("icon", "attack")
	return card["id"]


# ---------- shop ----------

func restock_shop() -> void:
	shop.clear()
	for i in SHOP_DEFENSES:
		shop.append(CardDB.get_card("defense"))
	var pool := CardDB.all()
	var total := 0
	for c in pool:
		total += int(c.get("count", 1))
	var tries := 0
	while shop.size() < SHOP_SLOTS and tries < 100:
		tries += 1
		var pick := rng.randi_range(1, total)  # weighted by how common the card is
		for c in pool:
			pick -= int(c.get("count", 1))
			if pick <= 0:
				if shop.count(c) < 2:  # at most 2 of the same card per restock (Defense: the fixed ones)
					shop.append(c)
				break


func _shop_open_for(p: PlayerData) -> String:
	if finished or not p.alive:
		return "เล่นไม่ได้แล้ว"
	if _hold > 0.0:
		return "รอให้ท่าโจมตีเล่นจบก่อน"
	if _opening > 0.0:
		return "รอทอยลำดับการเล่นก่อน"
	if minigame != null:
		return "รอ Minigame จบก่อน"
	if p != current() or step != Step.PHASE1:
		return "ร้านค้าเปิดเฉพาะช่วง Preparation (เตรียมตัว) ในเทิร์นของคุณ"
	if _pause > 0.0 or not pending_attack.is_empty():
		return "รอสักครู่"
	return ""


func can_buy(p: PlayerData, slot: int) -> String:
	var reason := _shop_open_for(p)
	if reason != "":
		return reason
	if p.has("no_shop"):
		return "คุณโดนคำสาป ห้ามซื้อของ"
	if slot < 0 or slot >= shop.size() or shop[slot].is_empty():
		return "ขายหมดแล้ว"
	if p.gold < int(shop[slot]["price"]):
		return "เงินไม่พอ"
	if shop[slot]["id"] == WARD and p.find_card(WARD) >= 0:
		return "ถือการ์ดนี้ได้คนละ 1 ใบ"
	return ""


## A full hand can still buy: the new card replaces the one at replace_index.
func hand_full(p: PlayerData) -> bool:
	return p.hand.size() >= hand_limit


func buy(p: PlayerData, slot: int, replace_index: int = -1) -> bool:
	var reason := can_buy(p, slot)
	if reason == "" and hand_full(p) and (replace_index < 0 or replace_index >= p.hand.size()):
		reason = "มือเต็ม (%d ใบ): เลือกการ์ดในมือที่จะทิ้ง" % hand_limit
	if reason != "":
		if is_human(p):
			_log("[color=#ff6b6b]%s[/color]" % reason, p.seat)
		return false
	if is_mirror():
		remote.call("buy", [slot, replace_index])
		return true
	var card := shop[slot]
	shop[slot] = {}
	p.gold -= int(card["price"])
	var dropped := ""
	if hand_full(p):
		dropped = p.hand[replace_index]["name"]
		discard.append(p.hand[replace_index])
		p.hand.remove_at(replace_index)
	p.hand.append(card)
	_log("%s ซื้อ [b]%s[/b] (%d เงิน)%s" % [p.display_name, card_name(p, card), card["price"],
		"" if dropped == "" else " ทิ้ง %s" % dropped], p.seat,
		"%s ซื้อ [b]การ์ด 1 ใบ[/b] (%d เงิน)" % [p.display_name, card["price"]])
	bought.emit(p.seat, card)
	_ward_check(p)
	state_changed.emit()
	return true


func can_exchange(p: PlayerData) -> String:
	var reason := _shop_open_for(p)
	if reason != "":
		return reason
	if rings_to_win <= 0:
		return "ห้องนี้ปิดการสะสมแหวน"
	if p.has("no_shop"):
		return "คุณโดนคำสาป ห้ามซื้อของ"
	if minigames_played < 1:
		return "แลกแหวนได้หลังจบ Minigame ครั้งแรก"
	if p.shards < SHARDS_PER_RING:
		return "เศษแหวนไม่พอ (ต้องใช้ %d)" % SHARDS_PER_RING
	return ""


func exchange_ring(p: PlayerData) -> bool:
	var reason := can_exchange(p)
	if reason != "":
		if is_human(p):
			_log("[color=#ff6b6b]%s[/color]" % reason, p.seat)
		return false
	if is_mirror():
		remote.call("exchange_ring", [])
		return true
	p.shards -= SHARDS_PER_RING
	p.rings += 1
	_log("[color=#f0c419]%s แลกเศษแหวนเป็น [b]แหวน[/b] (มี %d/%d วง)[/color]" % [
		p.display_name, p.rings, rings_to_win])
	if p.rings >= rings_to_win:
		_finish(p, "สะสมแหวนครบ %d วง" % rings_to_win)
	state_changed.emit()
	return true


# ---------- combat ----------

func _start_attack(a: PlayerData, t: PlayerData) -> void:
	var can_defend := t.find_card("defense") >= 0 and not t.has("no_items")
	if not can_defend:
		_resolve_attack(a, t, false)
	elif is_human(t):
		pending_attack = {"attacker": a.seat, "target": t.seat, "time": DEFENSE_SECONDS}
		attack_incoming.emit(a.seat, t.seat)
	else:
		_resolve_attack(a, t, BotBrain.wants_to_defend(self, t, a))


## The human target's answer to an incoming attack.
func respond_defense(use_card: bool) -> void:
	if pending_attack.is_empty():
		return
	if is_mirror():
		remote.call("respond_defense", [use_card])
		return
	var a := players[pending_attack["attacker"]]
	var t := players[pending_attack["target"]]
	pending_attack = {}
	_resolve_attack(a, t, use_card and t.find_card("defense") >= 0)
	state_changed.emit()


func _resolve_attack(a: PlayerData, t: PlayerData, defended: bool) -> void:
	if defended:
		if t.has("free_block"):
			# เสริมป้องกัน: this block doesn't use up the Defense card
			t.statuses["free_block"] -= 1
			if t.statuses["free_block"] <= 0:
				t.statuses.erase("free_block")
			_log("[color=#6fa8dc]%s ใช้ [b]ป้องกัน[/b] กันการโจมตีไว้ได้ (ป้องกันฟรี: การ์ดไม่หาย)[/color]" % t.display_name)
		else:
			var i := t.find_card("defense")
			discard.append(t.hand[i])
			t.hand.remove_at(i)
			_log("[color=#6fa8dc]%s ใช้ [b]ป้องกัน[/b] กันการโจมตีไว้ได้[/color]" % t.display_name)
		attacked.emit(a.seat, t.seat, true)
		return
	t.hp -= 1
	a.damage += 1
	_log("[color=#ff6b6b]%s เสียเลือด 1 (เหลือ %d)[/color]" % [t.display_name, t.hp])
	attacked.emit(a.seat, t.seat, false)
	if t.hp <= 0:
		_eliminate(t, a)


## `t` is out: knocked out by `by` (null: no one, e.g. a test).
func _eliminate(t: PlayerData, by: PlayerData) -> void:
	if by:
		by.kills += 1
	t.alive = false
	t.hp = 0
	discard.append_array(t.hand)
	t.hand.clear()
	t.statuses.clear()
	_log("[color=#ff6b6b][b]%s ตกรอบ![/b] (%s)[/color]" % [t.display_name, "โดย " + by.display_name if by else "ช่วงชี้ขาด"])
	if is_human(t) and not alive_players().any(func(q: PlayerData) -> bool: return is_human(q)):
		speed = maxf(speed, SPECTATE_SPEED)  # no one left to play: the bots finish it quickly
	var left := alive_players()
	if left.size() == 1:
		_finish(left[0], "เหลือรอดคนสุดท้าย")


func _finish(winner: PlayerData, why: String) -> void:
	finished = true
	win_reason = why
	_log("[color=#ffd76a][b]%s ชนะ! (%s)[/b][/color]" % [winner.display_name, why])
	game_over.emit(winner.seat)
	state_changed.emit()


# ---------- flow ----------

func _begin_step(s: Step) -> void:
	step = s
	time_left = step_seconds
	_bot_wait = rng.randf_range(0.6, 1.2)
	_bot_actions = 0
	if s == Step.ROLL:
		_pre_roll_items = 0
		_log("[color=#ffd76a]เทิร์นของ %s[/color]" % current().display_name)
	state_changed.emit()
	if s == Step.ROLL:
		turn_started.emit(current().seat)


## True while max HP or the hand limit can still drop (the countdown is worth showing).
func shrinking() -> bool:
	return max_hp > MIN_MAX_HP or hand_limit > MIN_HAND_LIMIT


## Each finished round counts down; at 0 max HP and the hand limit drop by 1 for everyone (HP
## above the new max is lost, cards over the new limit are discarded, newest first) and the
## count starts again from SHRINK_ROUNDS.
func _shrink_countdown() -> void:
	if not shrinking():
		return
	shrink_in -= 1
	if shrink_in > 0:
		return
	shrink_in = SHRINK_ROUNDS
	max_hp = maxi(MIN_MAX_HP, max_hp - 1)
	hand_limit = maxi(MIN_HAND_LIMIT, hand_limit - 1)
	_log("[color=#ff8a3c][b]ครบ %d รอบ:[/b] เลือดสูงสุดเหลือ %d · การ์ดในมือสูงสุดเหลือ %d[/color]" % [SHRINK_ROUNDS, max_hp, hand_limit])
	for p in alive_players():
		p.hp = mini(p.hp, max_hp)
		var dropped := 0
		while p.hand.size() > hand_limit:
			discard.append(p.hand.pop_back())
			dropped += 1
		if dropped > 0:
			_log("%s ทิ้งการ์ด %d ใบ (เกินจำนวนที่ถือได้)" % [p.display_name, dropped])
	showdown_shrunk.emit()


func _end_turn() -> void:
	_tick_statuses(current())
	var start := turn_index
	while true:
		turn_index += 1
		if turn_index >= order.size():
			turn_index = 0
			_end_round()
		if current().alive or turn_index == start:
			break
	if minigame == null:
		_begin_step(Step.ROLL)  # otherwise the next turn starts when the minigame closes


func _tick_statuses(p: PlayerData) -> void:
	for id: String in p.statuses.keys():
		if id in UNTIL_USED:
			continue  # bad luck lasts until the next roll, free blocks until used
		p.statuses[id] -= 1
		if p.statuses[id] <= 0:
			p.statuses.erase(id)
			_log("%s: %s หมดผลแล้ว" % [p.display_name, STATUS_NAMES[id]])


func _end_round() -> void:
	_log("จบรอบที่ %d" % round_no)
	_shrink_countdown()
	var play_minigame := minigames_enabled and round_no % MINIGAME_EVERY == 0
	round_no += 1
	restock_shop()
	_log("ร้านค้าเติมสินค้าใหม่")
	if play_minigame:
		_start_minigame()


# ---------- minigame ----------

func _start_minigame() -> void:
	var qs := Minigame.questions()
	if qs.is_empty():
		return
	if _question_bag.is_empty():
		_question_bag.assign(range(qs.size()))
		_question_bag.shuffle()
	var seats: Array[int] = []
	for s in order:
		if players[s].alive:
			seats.append(s)
	minigame = Minigame.new(qs[_question_bag.pop_back()], seats)
	_bot_wait = rng.randf_range(2.0, 3.0)  # time to read the question
	_log("[color=#c9a227][b]Minigame: ทายอันดับ[/b] · %s[/color]" % minigame.question["question"])
	minigame_started.emit()
	state_changed.emit()


func _minigame_tick(d: float) -> void:
	if minigame.done():
		_minigame_close -= d
		if _minigame_close <= 0.0:
			minigame = null
			minigame_changed.emit()
			_begin_step(Step.ROLL)
		return
	minigame.time_left -= d
	var p := players[minigame.current_seat()]
	if not is_human(p):
		_bot_wait -= d
		if _bot_wait <= 0.0:
			minigame_answer(p, BotBrain.minigame_answer(self, p, minigame))
	elif minigame.time_left <= 0.0:
		_log("หมดเวลา")
		minigame_answer(p, "")


## `p` names `text` in the minigame ("" = pass). Returns why it was refused, or "".
func minigame_answer(p: PlayerData, text: String) -> String:
	if minigame == null or minigame.done() or p.seat != minigame.current_seat():
		return "ยังไม่ถึงตาคุณ"
	var reason := minigame.check_answer(text)
	if reason != "":
		return reason
	if is_mirror():
		remote.call("minigame_answer", [text])
		return ""
	var e := minigame.submit(text)
	if e["text"] == "":
		_log("%s ไม่ตอบ (+0)" % p.display_name)
	elif e["rank"] == 0:
		_log("%s ตอบ %s · ไม่อยู่ในรายการ (+0)" % [p.display_name, e["text"]])
	else:
		_log("%s ตอบ %s · อันดับ %d (+%d)" % [p.display_name, e["text"], e["rank"], e["points"]])
	_bot_wait = rng.randf_range(1.0, 1.8)
	if minigame.done():
		_finish_minigame()
	minigame_changed.emit()
	return ""


func _finish_minigame() -> void:
	var results := minigame.results()
	for r in results:
		var p := players[r["seat"]]
		if rings_to_win <= 0:
			r["shards"] = 0  # rings off: the minigame pays gold only
		p.shards += r["shards"]
		p.gold += r["gold"]
		_log("[color=#f0c419]ที่ %d %s %d แต้ม → %sเงิน +%d[/color]" % [r["place"], p.display_name, r["score"],
			"เศษแหวน +%d, " % r["shards"] if rings_to_win > 0 else "", r["gold"]])
	minigames_played += 1
	_minigame_close = MINIGAME_RESULT_SECONDS
	minigame_finished.emit(results)
	state_changed.emit()


func _bot_act() -> void:
	var p := current()
	var choice := {} if _bot_actions >= 5 else BotBrain.choose(self, p)
	var done := false
	if choice.has("exchange"):
		done = exchange_ring(p)
	elif choice.has("buy"):
		done = buy(p, choice["buy"], choice.get("replace", -1))
	elif choice.has("index"):
		done = play_card(p, choice["index"], choice.get("target", -1))
	if done:
		_bot_actions += 1
	else:
		advance()
	_bot_wait = rng.randf_range(0.6, 1.2)


func _draw(p: PlayerData, n: int, announce: bool) -> Array[String]:
	var drawn: Array[String] = []
	var left := n
	var redraws := 0
	while left > 0:
		left -= 1
		if deck.is_empty():
			if discard.is_empty():
				break
			deck = discard.duplicate()
			discard.clear()
			CardDB.shuffle(deck, rng)
			_log("สับกองทิ้งกลับเป็นกองจั่ว")
		var card: Dictionary = deck.pop_back()
		if card["id"] == WARD and p.find_card(WARD) >= 0 and redraws < 3:
			discard.append(card)  # only one per hand: set aside, draw another
			redraws += 1
			left += 1
			continue
		if p.hand.size() >= hand_limit:
			discard.append(card)
			_log("%s มือเต็ม (%d ใบ) ทิ้งการ์ดที่จั่ว" % [p.display_name, hand_limit])
		else:
			p.hand.append(card)
			drawn.append(card["name"])
	if announce and not drawn.is_empty():
		_log("คุณจั่วได้: " + ", ".join(drawn), p.seat, "%s จั่วการ์ด %d ใบ" % [p.display_name, drawn.size()])
	return drawn


## A line in the history. `owner` >= 0: only that seat sees `text`, the others see `others`
## ("" = nothing): what you bought or drew stays yours.
func _log(text: String, owner := -1, others := "") -> void:
	if autoplay:
		print(text)  # smoke-test logs show the whole game flow
	var mine := owner < 0 or (owner == 0 and is_human(players[0]))
	var shown := text if mine else others
	if shown != "":
		log_added.emit(shown)
	log_entry.emit(owner, text, others)
