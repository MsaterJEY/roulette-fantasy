class_name BotBrain
extends RefCounted
## Simple rule-based bot decisions. Returns {"index": hand index, "target": seat},
## {"buy": slot} (with "replace": hand index when the hand is full), {"exchange": true}, or {} to pass. Also answers minigame questions.

const KEEP_DEFENSES := 2  # defense cards a bot likes to hold
const KEEP_ATTACKS := 2
const CURSE_BUY_GOLD := 7  # spare gold before a bot buys a curse card
const MINIGAME_PASS_CHANCE := 0.1  # bot can't think of anything
const MINIGAME_SPREAD := 6.0  # how far down the list a bot's answer tends to land


static func choose(game: GameController, p: PlayerData) -> Dictionary:
	if game.step == GameController.Step.ROLL:
		return {}  # roll straight away
	if game.step == GameController.Step.PHASE1:
		var shopping := _shop_choice(game, p)
		if not shopping.is_empty():
			return shopping
	var heal := _best_heal(game, p)
	if heal >= 0:
		return {"index": heal}
	# help and curse cards first, so e.g. "no items" lands before the attack it sets up
	for i in p.hand.size():
		var card: Dictionary = p.hand[i]
		if game.can_play(p, card) != "":
			continue
		match card["id"]:
			"gain_defense":
				# only worth it while holding a Defense card to keep
				if _count(p, "defense") > 0 and not p.has("free_block"):
					return {"index": i}
			"cleanse_1", "cleanse_all":
				if GameController.CURSES.any(func(c: String) -> bool: return p.has(c)):
					return {"index": i, "target": p.seat}
			"truce":
				if p.hp <= 2 and _count(p, "defense") == 0:
					return {"index": i}
			"no_items", "no_shop", "bad_luck", "blind":
				var t := _curse_target(game, p, card)
				if t >= 0:
					return {"index": i, "target": t}
	for i in p.hand.size():
		var card: Dictionary = p.hand[i]
		if card["id"] == "attack" and game.can_play(p, card) == "":
			return {"index": i, "target": _best_target(game, p, card)}
	return {}


## Who to curse with `card`, or -1 to keep it for later. Aims at the leader and only
## when the curse hurts them now.
static func _curse_target(game: GameController, p: PlayerData, card: Dictionary) -> int:
	var seat := _best_target(game, p, card)
	if seat < 0:
		return -1
	var t := game.players[seat]
	if t.has(card["id"]):
		return -1
	match card["id"]:
		"no_items":  # set up an attack: they can't defend this turn
			if game.step == GameController.Step.PHASE2 and _count(p, "attack") > 0 and not t.hand.is_empty():
				return seat
		"no_shop":  # stops buying and ring exchange
			if t.shards >= 2 or t.gold >= 6:
				return seat
		"blind":
			if t.hand.size() >= 3:
				return seat
		"bad_luck":
			return seat
	return -1


## A minigame answer: usually an unused item near the top of the list, sometimes a pass.
static func minigame_answer(game: GameController, _p: PlayerData, mg: Minigame) -> String:
	if game.rng.randf() < MINIGAME_PASS_CHANCE:
		return ""
	var items: Array = mg.question["items"]
	var free: Array[int] = []
	for i in items.size():
		if not mg.used.has(i):
			free.append(i)
	if free.is_empty():
		return ""
	var k := mini(int(absf(game.rng.randfn(0.0, MINIGAME_SPREAD))), free.size() - 1)
	return items[free[k]]["name"]


## Heal card worth playing now, or -1. Only when hurt, choosing the smallest card that
## does the job; heal 2 at 4/5 HP (wasting a point) only in an emergency (HP 1–2).
static func _best_heal(game: GameController, p: PlayerData) -> int:
	var missing := game.max_hp - p.hp
	if missing <= 0:
		return -1
	var gains := {"heal_1": 1, "heal_2": 2}
	var best := -1
	var best_gain := 0
	for i in p.hand.size():
		var id: String = p.hand[i]["id"]
		if not gains.has(id) or game.can_play(p, p.hand[i]) != "":
			continue
		var gain: int = mini(gains[id], missing)
		if gains[id] > gain and p.hp > 2:
			continue  # would waste healing
		if gain > best_gain or (gain == best_gain and gains[id] < gains[p.hand[best]["id"]]):
			best = i
			best_gain = gain
	return best


## Rings first; then the most needed card in the shop: Defense while short of them (more
## when low on HP), healing when hurt, an Attack to hit back, a free block, and with spare
## gold one curse. Scored rather than first-come, so a bot doesn't spend its gold on the
## first Attack in the row while a Defense sits further along.
static func _shop_choice(game: GameController, p: PlayerData) -> Dictionary:
	if game.can_exchange(p) == "":
		return {"exchange": true}
	if game.hand_full(p):
		return _swap_for_attack(game, p)
	var best := -1
	var best_score := 0.0
	for slot in game.shop.size():
		if game.can_buy(p, slot) != "":
			continue
		var score := _shop_score(game, p, game.shop[slot])
		if score > best_score:
			best_score = score
			best = slot
	return {"buy": best} if best >= 0 else {}


## A full hand with no Attack card (it happens once the hand limit has shrunk: drawn cards
## are thrown away): swap a spare card, a Defense beyond the first or else the least useful
## one, for an Attack from the shop, so the bot can still fight.
static func _swap_for_attack(game: GameController, p: PlayerData) -> Dictionary:
	if _count(p, "attack") > 0:
		return {}
	var slot := -1
	for i in game.shop.size():
		if not game.shop[i].is_empty() and game.shop[i]["id"] == "attack" and game.can_buy(p, i) == "":
			slot = i
			break
	if slot < 0:
		return {}
	var drop := -1
	if _count(p, "defense") >= 2:
		drop = p.find_card("defense")
	else:
		for i in p.hand.size():
			if not p.hand[i]["id"] in ["defense", GameController.WARD]:
				drop = i
				break
	return {"buy": slot, "replace": drop} if drop >= 0 else {}


static func _shop_score(game: GameController, p: PlayerData, card: Dictionary) -> float:
	var defenses := _count(p, "defense")
	# a shrunk hand can't hold many: leave room for an Attack
	var keep_defenses := mini(KEEP_DEFENSES + (1 if p.hp <= 2 else 0), game.hand_limit - 1)
	var id: String = card["id"]
	var price := int(card["price"])
	# without a Defense card, keep enough gold to buy one next time
	var reserve := int(CardDB.get_card("defense")["price"]) if defenses == 0 and id != "defense" else 0
	if p.gold - price < reserve:
		return 0.0
	match id:
		"defense":
			return 100.0 - defenses * 15.0 if defenses < keep_defenses else 0.0
		"heal_1", "heal_2":
			var missing := game.max_hp - p.hp
			if missing <= 0 or p.hp > 3:
				return 0.0
			return (90.0 if p.hp <= 2 else 50.0) + (5.0 if (id == "heal_2") == (missing >= 2) else 0.0)
		"attack":
			var attacks := _count(p, "attack")
			return (60.0 if attacks == 0 else 30.0) if attacks < KEEP_ATTACKS else 0.0
		"gain_defense":
			return 40.0 if defenses > 0 and _count(p, "gain_defense") == 0 else 0.0
		GameController.WARD:  # can_buy already stops a second one
			return 25.0 if p.hand.size() <= 5 else 0.0
	if card["type"] == "curse" and id != "truce" and p.gold >= CURSE_BUY_GOLD 			and p.hand.size() <= 4 and _count_type(p, "curse") == 0:
		return 20.0
	return 0.0


static func _count_type(p: PlayerData, type: String) -> int:
	return p.hand.filter(func(c: Dictionary) -> bool: return c["type"] == type).size()


static func _count(p: PlayerData, id: String) -> int:
	return p.hand.filter(func(c: Dictionary) -> bool: return c["id"] == id).size()


static func wants_to_defend(_game: GameController, _target: PlayerData, _attacker: PlayerData) -> bool:
	return true


## Pick the leader (most rings, then shards); among equals the one with the least HP
## and fewest cards (fewer cards = less likely to hold a Defense).
static func _best_target(game: GameController, p: PlayerData, card: Dictionary) -> int:
	var best := -1
	var best_score := -INF
	for seat in game.valid_targets(p, card):
		var t := game.players[seat]
		var score := t.rings * 100.0 + t.shards * 10.0 - t.hp - t.hand.size() * 0.5 + game.rng.randf()
		if score > best_score:
			best_score = score
			best = seat
	return best
