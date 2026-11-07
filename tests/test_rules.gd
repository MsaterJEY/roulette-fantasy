extends SceneTree
## Rules tests without the UI. Run:
##   Godot_console.exe --headless --path . -s res://tests/test_rules.gd
## Prints PASS/FAIL per check and exits with code 1 if anything failed.

var failures := 0


func _initialize() -> void:
	test_attack_and_defense()
	test_elimination_and_win()
	test_curses()
	test_play_rules()
	test_shop()
	test_no_wasted_restores()
	test_minigame_scoring()
	test_minigame_flow()
	test_minigame_questions()
	test_forfeit()
	test_bot_curses()
	test_result_order()
	test_buy_with_full_hand()
	test_bot_shopping()
	test_opening_order()
	test_characters()
	test_room_switches()
	test_showdown()
	test_ward()
	print("RULES %s (%d failed)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  " + what)
	else:
		failures += 1
		print("FAIL  " + what)


func new_game() -> GameController:
	var g := GameController.new()
	root.add_child(g)
	g.start_game(["คุณ", "บอท A", "บอท B", "บอท C"])
	g._opening = 0.0  # skip the roll-off show
	for p in g.players:
		p.hand.clear()
	g.order.assign([0, 1, 2, 3])
	g.turn_index = 0
	g.step = GameController.Step.PHASE2
	return g


func card(id: String) -> Dictionary:
	return CardDB.get_card(id)


func test_attack_and_defense() -> void:
	var g := new_game()
	var me := g.players[0]
	var a := g.players[1]
	# no defense card: 1 HP lost straight away (there is no shield stat any more)
	var hits: Array = []
	g.attacked.connect(func(_att: int, tgt: int, blocked: bool) -> void: hits.append([tgt, blocked]))
	me.hand.append(card("attack"))
	check(g.play_card(me, 0, 1), "human can attack a bot in Combat")
	check(a.hp == PlayerData.MAX_HP - 1, "undefended attack costs 1 HP")
	check(hits == [[1, false]], "attacked signal reports a hit (not blocked)")
	# bot with a defense card blocks
	me.hand.append(card("attack"))
	a.hand.append(card("defense"))
	g.play_card(me, 0, 1)
	check(a.hp == PlayerData.MAX_HP - 1 and a.hand.is_empty(), "bot blocks with its defense card, which is used up")
	check(hits.back() == [1, true], "attacked signal reports the block")
	# bot attacks the human, who holds a defense card -> waits for the human
	g.turn_index = 1
	a.hand.append(card("attack"))
	me.hand.append(card("defense"))
	g.play_card(a, 0, 0)
	check(not g.pending_attack.is_empty(), "attack on the human waits for a defense answer")
	g.respond_defense(true)
	check(g.pending_attack.is_empty() and me.hand.is_empty() and me.hp == PlayerData.MAX_HP, "human defends: no HP lost, card used up")
	a.hand.append(card("attack"))
	me.hand.append(card("defense"))
	g.play_card(a, 0, 0)
	g.respond_defense(false)
	check(me.hp == PlayerData.MAX_HP - 1 and me.hand.size() == 1, "human declines: loses 1 HP, keeps the card")
	g.queue_free()


func test_elimination_and_win() -> void:
	var g := new_game()
	var me := g.players[0]
	for i in [2, 3]:
		g.players[i].alive = false
	var a := g.players[1]
	a.hp = 1
	me.hand.append(card("attack"))
	g.play_card(me, 0, 1)
	check(not a.alive, "HP 0 eliminates the player")
	check(g.finished, "last player alive wins")
	g.queue_free()


func test_curses() -> void:
	var g := new_game()
	var me := g.players[0]
	var a := g.players[1]
	me.hand.append(card("no_items"))
	g.play_card(me, 0, 1)
	check(a.has("no_items"), "curse lands on the target")
	a.hand.append(card("heal_1"))
	g.turn_index = 1
	check(g.can_play(a, a.hand[0]) != "", "no_items blocks playing cards")
	g._end_turn()
	check(not a.has("no_items"), "1-turn curse ends after the target's turn")
	# truce: nobody can attack the user
	g.turn_index = 0
	me.hand.append(card("truce"))
	g.play_card(me, 0)
	a.hand.append(card("attack"))
	g.turn_index = 1
	check(not 0 in g.valid_targets(a, a.hand[0]), "truce user cannot be attacked")
	# bad luck lowers the next dice-roll gold (never below 1)
	g.turn_index = 2
	g.step = GameController.Step.ROLL
	var b := g.players[2]
	b.statuses["bad_luck"] = 1
	g._pause = 0.0
	g.roll_dice()
	check(not b.has("bad_luck"), "bad luck is used up by the next roll")
	g.queue_free()


func test_play_rules() -> void:
	var g := new_game()
	var me := g.players[0]
	me.hand.append(card("attack"))
	g.step = GameController.Step.PHASE1
	check(g.can_play(me, me.hand[0]) != "", "attack is Combat only")
	me.hand.clear()
	me.hand.append(card("defense"))
	g.step = GameController.Step.PHASE2
	check(g.can_play(me, me.hand[0]) != "", "defense cannot be played on your own turn")
	me.hand.clear()
	g.step = GameController.Step.ROLL
	for i in 3:
		me.hand.append(card("heal_1"))
	me.hp = 1
	g.play_card(me, 0)
	g.play_card(me, 0)
	check(not g.play_card(me, 0), "max 2 cards before rolling")
	check(me.hp == 3, "heals applied")
	g.queue_free()


func test_shop() -> void:
	var g := new_game()
	var me := g.players[0]
	g.step = GameController.Step.PHASE1
	g.shop.assign([CardDB.get_card("attack"), CardDB.get_card("heal_1"), {}, {}, {}])
	me.gold = 3
	check(g.buy(me, 0) and me.gold == 1 and me.hand.size() == 1, "buy a card: gold paid, card in hand")
	check(g.shop[0].is_empty(), "bought slot is sold out")
	check(g.can_buy(me, 1) == "เงินไม่พอ", "cannot buy without enough gold")
	me.gold = 10
	me.statuses["no_shop"] = 2
	check(g.can_buy(me, 1) != "", "no_shop curse blocks buying")
	me.statuses.clear()
	g.step = GameController.Step.PHASE2
	check(g.can_buy(me, 1) != "", "shop is Preparation only")
	g.step = GameController.Step.PHASE1
	me.shards = GameController.SHARDS_PER_RING
	check(g.can_exchange(me) != "", "no ring exchange before the first minigame")
	g.minigames_played = 1
	check(g.exchange_ring(me) and me.rings == 1 and me.shards == 0, "%d shards -> 1 ring" % GameController.SHARDS_PER_RING)
	me.rings = PlayerData.RINGS_TO_WIN - 1
	me.shards = GameController.SHARDS_PER_RING
	g.exchange_ring(me)
	check(g.finished, "5th ring wins the game")
	g.queue_free()


func test_no_wasted_restores() -> void:
	var g := new_game()
	var me := g.players[0]
	me.hand.append(card("heal_1"))
	check(g.can_play(me, me.hand[0]) == "เลือดเต็มอยู่แล้ว", "cannot heal at full HP")
	me.hand.clear()
	me.hand.append(card("gain_defense"))
	check(g.play_card(me, 0) and me.statuses.get("free_block") == 1, "เสริมป้องกัน gives one free block")
	g._end_turn()
	check(me.has("free_block"), "free block does not expire at the end of the turn")
	# a bot attacks; the human blocks and keeps the Defense card
	var a := g.players[1]
	g.turn_index = 1
	g.step = GameController.Step.PHASE2
	me.hand.assign([card("defense")])
	a.hand.assign([card("attack")])
	g.play_card(a, 0, 0)
	g.respond_defense(true)
	check(me.hp == PlayerData.MAX_HP and me.hand.size() == 1 and not me.has("free_block"),
		"free block: blocked, card kept, free block used up")
	a.hand.assign([card("attack")])
	g.play_card(a, 0, 0)
	g.respond_defense(true)
	check(me.hp == PlayerData.MAX_HP and me.hand.is_empty(), "next block uses the card up again")
	g.turn_index = 0
	g.step = GameController.Step.PHASE1
	var bot := g.players[1]
	g.turn_index = 1
	g.step = GameController.Step.PHASE1
	bot.hand.assign([card("heal_2"), card("heal_1")])
	check(BotBrain._best_heal(g, bot) == -1, "bot at full HP plays no heal")
	bot.hp = PlayerData.MAX_HP - 1
	var heal := BotBrain._best_heal(g, bot)
	check(heal >= 0 and bot.hand[heal]["id"] == "heal_1", "bot missing 1 HP uses heal 1, not heal 2")
	bot.hp = PlayerData.MAX_HP - 2
	heal = BotBrain._best_heal(g, bot)
	check(heal >= 0 and bot.hand[heal]["id"] == "heal_2", "bot missing 2 HP uses heal 2")
	g.queue_free()


func test_minigame_scoring() -> void:
	var q := {"question": "q", "items": [
		{"name": "จีน", "aliases": ["china"]}, {"name": "อินเดีย", "aliases": ["india"]},
		{"name": "ไทย", "aliases": ["thailand"]}]}
	var mg := Minigame.new(q, [2, 0, 1] as Array[int])
	check(mg.current_seat() == 2, "minigame answers go in the given order")
	var e := mg.submit("  China ")
	check(e["rank"] == 1 and e["points"] == 100 and e["text"] == "จีน", "alias with spaces/case counts: rank 1 = 100 points")
	check(mg.check_answer("จีน") != "", "an item already named can't be named again (other spelling)")
	check(mg.submit("จีน").is_empty() and mg.current_seat() == 0, "refused repeat keeps the same player's turn")
	e = mg.submit("ลาว")
	check(e["rank"] == 0 and e["points"] == 0, "answer not in the list scores 0")
	check(mg.check_answer("ลาว") != "", "the same wrong answer can't be repeated either")
	e = mg.submit("")
	check(e["points"] == 0 and mg.round_no == 2, "empty = pass; after everyone answers the next round starts")
	mg.submit("ไทย")   # seat 2: +98
	mg.submit("india")  # seat 0: +99
	mg.submit("")       # seat 1
	for i in 3:
		mg.submit("")
	check(mg.done(), "done after %d rounds" % Minigame.ROUNDS)
	var r := mg.results()
	check(r[0]["seat"] == 2 and r[0]["score"] == 198 and r[0]["shards"] == 3 and r[0]["gold"] == 10,
		"1st place gets 3 shards + 10 gold")
	check(r[1]["seat"] == 0 and r[1]["shards"] == 2 and r[1]["gold"] == 5, "2nd place gets 2 shards + 5 gold")
	check(r[2]["seat"] == 1 and r[2]["shards"] == 1 and r[2]["gold"] == 5, "3rd place gets 1 shard + 5 gold")
	var tie := Minigame.new(q, [0, 1] as Array[int])
	tie.submit("")
	tie.submit("")
	check(tie.results().all(func(x: Dictionary) -> bool: return x["place"] == 1 and x["shards"] == 3),
		"equal scores share the place and its reward")


func test_minigame_flow() -> void:
	var g := new_game()
	g.step = GameController.Step.PHASE2
	g.round_no = 2
	g.turn_index = 3
	g.players[2].alive = false
	g._end_turn()
	check(g.minigame != null, "minigame starts at the end of round 2")
	check(g.minigame.seats == ([0, 1, 3] as Array[int]), "only living players take part")
	check(g.round_no == 3 and g.turn_index == 0, "the next round is set up")
	var me := g.players[0]
	me.hand.append(card("heal_1"))
	me.hp = 3
	check(not g.play_card(me, 0), "no cards can be played during the minigame")
	g.advance()
	check(g.minigame != null, "advance() does nothing during the minigame")
	check(g.minigame_answer(g.players[1], "x") != "", "answering out of turn is refused")
	var first: String = g.minigame.question["items"][0]["name"]
	check(g.minigame_answer(me, first) == "", "your answer is accepted on your turn")
	var shards_before := me.shards
	var gold_before := me.gold
	while not g.minigame.done():
		g.minigame_answer(g.players[g.minigame.current_seat()], "")
	check(me.shards == shards_before + 3 and me.gold == gold_before + 10, "winner's reward is paid out")
	check(g.minigames_played == 1, "minigame counted (ring exchange opens)")
	g._process(GameController.MINIGAME_RESULT_SECONDS + 0.1)
	check(g.minigame == null and g.step == GameController.Step.ROLL and g.current() == me,
		"after the results the next turn starts with a roll")
	# bots answer by themselves, never repeating
	g.autoplay = true
	g.round_no = 4
	g.turn_index = g.order.size() - 1
	g._end_turn()
	var guard := 0
	while g.minigame != null and not g.minigame.done() and guard < 1000:
		g._process(0.5)
		guard += 1
	var named: Array = g.minigame.answers.filter(func(a: Dictionary) -> bool: return a["text"] != "") 		.map(func(a: Dictionary) -> String: return a["text"])
	var unique := {}
	for n: String in named:
		unique[n] = true
	check(g.minigame.done() and unique.size() == named.size(), "bots finish the minigame without repeats")


func test_minigame_questions() -> void:
	var packed: Array[Dictionary] = Minigame.questions().duplicate()
	var one := {"question": "q", "items": [{"name": "a", "aliases": ["b"]}]}
	for bad: Variant in [null, "x", [], [{}], [{"question": "q", "items": []}],
			[{"question": "q", "items": [{"name": ""}]}],
			[{"question": "q", "items": [{"name": "a", "aliases": [1]}]}]]:
		check(not Minigame.use_questions(bad), "a bad list is refused: %s" % str(bad))
	check(Minigame.questions() == packed, "after a bad list the packed questions stay")
	check(Minigame.use_questions([{}, one]) and Minigame.questions() == ([one] as Array[Dictionary]),
		"a good list replaces the questions, without its bad entries")

	var g := new_game()
	Minigame.use_questions(packed)
	g._start_minigame()
	Minigame.use_questions([one])  # the database answers after the bag was filled
	for i in packed.size() - 1:
		g._start_minigame()
		check(packed.has(g.minigame.question), "a list arriving mid-game can't break the draw")
	g._start_minigame()
	check(g.minigame.question == one, "the next bag uses the new list")
	Minigame.use_questions(packed)

	var seed_file := ProjectSettings.globalize_path("res://web/api/questions_seed.json")
	check(FileAccess.get_file_as_string(seed_file) == FileAccess.get_file_as_string(Minigame.PATH),
		"the database's first fill (web/api/questions_seed.json) matches data/minigame_ranks.json")


func test_forfeit() -> void:
	var g := new_game()
	var p := g.players[0]
	p.rings = 2
	p.shards = 1
	p.kills = 1
	p.damage = 3
	p.hand.append(CardDB.get_card("attack"))
	g.forfeit(p)
	check(not p.alive and p.hp == 0 and p.hand.is_empty(), "leaving: out at once, cards gone")
	check(p.rings == 2 and p.shards == 1 and p.kills == 1 and p.damage == 3, "what they had earned still counts")
	check(g.current() == g.players[1] and g.step == GameController.Step.ROLL, "their turn passes to the next player")
	check(not g.finished, "the others play on")
	g.forfeit(p)
	check(g.alive_players().size() == 3, "leaving twice changes nothing")
	var ranked := ResultPanel.standings(g, 1)
	check(ranked[-1] == p, "ranked with those knocked out")

	g = new_game()
	g.pending_attack = {"attacker": 1, "target": 0, "time": 5.0}
	g.turn_index = 1
	g.forfeit(g.players[0])
	check(g.pending_attack.is_empty() and g.current() == g.players[1], "an attack on them is dropped, the attacker's turn goes on")
	g = new_game()
	g.pending_attack = {"attacker": 0, "target": 1, "time": 5.0}
	g.forfeit(g.players[0])
	check(g.pending_attack.is_empty() and g.current() == g.players[1], "their own attack is dropped too")

	g = new_game()
	g._start_minigame()
	g.turn_index = 1  # the next turn, once the minigame closes
	var mg := g.minigame
	mg.seats.assign([0, 1, 2, 3])
	mg.turn = 1
	g.forfeit(g.players[1])
	check(mg.seats == ([0, 2, 3] as Array[int]) and mg.current_seat() == 2, "minigame: their answer turn passes on")
	check(g.current() == g.players[2], "the next turn skips them too")
	g.forfeit(g.players[3])
	check(mg.seats == ([0, 2] as Array[int]) and not g.finished, "minigame goes on without them")
	g.forfeit(g.players[2])
	check(g.finished and g.players[0].alive, "the last one left wins")

	g = new_game()
	g._opening = 5.0
	g.forfeit(g.players[0])
	check(g.current() == g.players[1] and g.in_opening(), "leaving during the opening: the first turn goes to the next player")

	var two := Minigame.new({"question": "q", "items": [{"name": "a"}]}, [0, 1] as Array[int])
	two.submit("")
	two.submit("")
	two.submit("")
	two.remove_seat(1)  # the last answer of the round was theirs
	check(two.round_no == 3 and two.current_seat() == 0, "leaving on the last turn of a round starts the next")


func test_bot_curses() -> void:
	var g := new_game()
	var b := g.players[1]
	var leader := g.players[2]
	leader.rings = 2
	leader.shards = 2
	g.step = GameController.Step.PHASE1
	g.turn_index = 1
	g.shop.clear()  # nothing to buy: only the card choice is tested
	b.hand.append(card("no_shop"))
	var c := BotBrain.choose(g, b)
	check(c.get("target", -1) == 2, "bot aims no-shop at the leader holding shards")
	b.hand.clear()
	b.hand.append(card("no_items"))
	check(BotBrain.choose(g, b).is_empty(), "bot keeps no-items when it has no attack to follow up")
	g.step = GameController.Step.PHASE2
	b.hand.append(card("attack"))
	leader.hand.append(card("defense"))
	c = BotBrain.choose(g, b)
	check(c.get("index", -1) == 0 and c.get("target", -1) == 2, "bot plays no-items before attacking the leader")


func test_result_order() -> void:
	var g := new_game()
	g.players[0].alive = false
	g.players[1].rings = 1
	g.players[3].rings = 3
	var order := ResultPanel.standings(g, 2).map(func(p: PlayerData) -> int: return p.seat)
	check(order == [2, 3, 1, 0], "results: winner, then rings, knocked-out players last")


func test_buy_with_full_hand() -> void:
	var g := new_game()
	var me := g.players[0]
	g.step = GameController.Step.PHASE1
	me.gold = 10
	for i in GameController.HAND_LIMIT:
		me.hand.append(card("defense"))
	me.hand[2] = card("attack")
	g.shop.assign([card("heal_1")])
	check(g.can_buy(me, 0) == "", "a full hand may still buy")
	check(not g.buy(me, 0), "buying with a full hand needs a card to replace")
	check(me.gold == 10 and g.shop[0]["id"] == "heal_1", "refused buy costs nothing")
	check(g.buy(me, 0, 2), "buy replacing the card at index 2")
	check(me.hand.size() == GameController.HAND_LIMIT and me.find_card("attack") < 0 and me.find_card("heal_1") >= 0,
		"the chosen card is swapped for the new one")
	check(me.gold == 7 and g.discard.back()["id"] == "attack", "paid, and the old card goes to the discard pile")
	var bot := g.players[1]
	for i in GameController.HAND_LIMIT:
		bot.hand.append(card("defense"))
	g.turn_index = 1
	g.shop.assign([card("heal_1")])
	bot.gold = 10
	check(not BotBrain._shop_choice(g, bot).has("buy"), "bots with a full hand don't buy just anything")
	g.shop.assign([card("attack")])
	var swap := BotBrain._shop_choice(g, bot)
	check(swap.get("buy", -1) == 0 and bot.hand[swap.get("replace", 0)]["id"] == "defense",
		"a full hand with no Attack swaps a spare Defense for one")


func test_bot_shopping() -> void:
	var g := new_game()
	g.restock_shop()
	check(g.shop.filter(func(c: Dictionary) -> bool: return c["id"] == "defense").size() >= GameController.SHOP_DEFENSES,
		"every restock offers the fixed Defense cards")
	var bot := g.players[1]
	g.turn_index = 1
	g.step = GameController.Step.PHASE1
	bot.gold = 10
	g.shop.assign([card("attack"), card("attack"), card("defense")])
	check(BotBrain._shop_choice(g, bot).get("buy", -1) == 2, "bot without Defense buys one before an Attack further left")
	bot.hand.assign([card("defense"), card("defense")])
	check(BotBrain._shop_choice(g, bot).get("buy", -1) == 0, "bot with 2 Defense buys an Attack")
	bot.hand.clear()
	bot.gold = 3
	g.shop.assign([card("heal_1")])
	bot.hp = PlayerData.MAX_HP - 1
	check(BotBrain._shop_choice(g, bot).is_empty(), "bot with no Defense keeps gold for one instead of a heal")


func test_opening_order() -> void:
	var g := new_game()
	var ok := true
	var ties := 0
	for i in 300:
		g.rng.seed = i
		g._roll_for_order()
		var by_seat := {}
		for r in g.opening_rolls:
			by_seat[r["seat"]] = r["totals"]
			ties += 1 if r["totals"].size() > 1 else 0
		for k in range(g.order.size() - 1):
			var a: Array = by_seat[g.order[k]]
			var b: Array = by_seat[g.order[k + 1]]
			var first_diff := -1
			for j in mini(a.size(), b.size()):
				if a[j] != b[j]:
					first_diff = j
					break
			# each player is ahead of the next: higher at the first throw where they differ
			if first_diff < 0 or a[first_diff] < b[first_diff]:
				ok = false
	check(ok, "turn order = highest opening total first, ties settled by re-throws (300 games)")
	check(ties > 0, "ties happened and were re-thrown (%d players re-threw)" % ties)
	var sorted_order := g.order.duplicate()
	sorted_order.sort()
	check(sorted_order == [0, 1, 2, 3], "everyone gets exactly one place")
	var g2 := GameController.new()
	root.add_child(g2)
	g2.start_game(["คุณ", "บอท A", "บอท B", "บอท C"])
	check(g2.in_opening() and g2.can_play(g2.players[0], card("heal_1")) != "", "no playing during the opening roll-off")
	g2._process(GameController.OPENING_WAIT_SECONDS - 0.5)
	check(g2.in_opening() and g2.opening_wait_left() > 0.0, "a short wait before the opening throws")
	g2._process(0.5 + GameController.OPENING_THROW_SECONDS * 4 + GameController.OPENING_SHOW_SECONDS + 0.1)
	check(not g2.in_opening() and g2.current().seat == g2.order[0] and g2.step == GameController.Step.ROLL,
		"after the roll-off the highest roller starts")


func test_characters() -> void:
	var ids := CharacterDB.ids()
	check(ids.size() == 4, "four playable characters")
	var g := GameController.new()
	root.add_child(g)
	g.start_game(["คุณ", "a", "b", "c"], ids)
	var me := g.players[0]
	check(me.character == ids[0] and g.players[3].character == ids[3], "each seat gets its character")
	var weapon: String = CharacterDB.get_character(ids[0])["weapon"]
	check(g.card_name(me, card("attack")) == weapon, "your Attack card is called after your weapon")
	check(g.card_icon(me, card("attack")) == CharacterDB.get_character(ids[0])["icon"], "and shows the weapon icon")
	check(g.card_name(me, card("defense")) == card("defense")["name"], "other cards keep their names")
	for c in CharacterDB.all():
		check(AttackFx.IMPACT.has(c["style"]) and AttackFx.FINISH.has(c["style"]), "%s has an attack and a finisher" % c["name_en"])
	g._opening = 0.0
	g.hold(1.0)
	var t := g.time_left
	g._process(0.5)
	check(g.time_left == t, "while held for an animation, the game waits")
	var you := g.players[0]
	g.turn_index = g.order.find(0)
	g.step = GameController.Step.PHASE1
	you.hand.assign([card("heal_1")])
	you.hp = 2
	check(g.can_play(you, you.hand[0]) != "" and g.can_buy(you, 0) != "", "no cards or shopping until the animation ends")
	g.advance()
	check(g.step == GameController.Step.PHASE1, "the Next button does nothing until the animation ends")
	g._process(1.0)
	check(not g.is_held() and g.can_play(you, you.hand[0]) == "", "after the animation, play goes on")


## Room settings: minigames off (no minigame at the end of round 2) and rings off (no ring
## exchange, a minigame pays gold only).
func test_room_switches() -> void:
	var g := new_game()
	g.minigames_enabled = false
	g.step = GameController.Step.PHASE2
	g.round_no = 2
	g.turn_index = g.order.size() - 1
	g._end_turn()
	check(g.minigame == null and g.round_no == 3, "minigames off: round 2 ends without a minigame")

	g = new_game()
	g.rings_to_win = 0
	var me := g.players[0]
	me.shards = 4
	g.minigames_played = 1
	check(g.can_exchange(me) != "" and not g.exchange_ring(me) and me.rings == 0, "rings off: no ring exchange")
	g.step = GameController.Step.PHASE2
	g.round_no = 2
	g.turn_index = g.order.size() - 1
	g._end_turn()
	var first: String = g.minigame.question["items"][0]["name"]
	var shards_before := me.shards
	var gold_before := me.gold
	g.minigame_answer(me, first)  # you score in round 1, then everyone passes
	while not g.minigame.done():
		g.minigame_answer(g.players[g.minigame.current_seat()], "")
	check(me.shards == shards_before and me.gold > gold_before, "rings off: the minigame pays gold, no shards")


## Shrinking table: every SHRINK_ROUNDS finished rounds max HP and the hand limit drop by 1
## for everyone (HP over the max is lost, extra cards discarded); no HP drain otherwise.
func test_showdown() -> void:
	var g := new_game()
	var p := g.players[0]
	var q := g.players[1]
	q.hand.clear()
	for i in GameController.HAND_LIMIT:
		q.hand.append(card("attack"))
	for r in GameController.SHRINK_ROUNDS - 1:
		g._end_round()
	g._minigame_close = 0.0
	g.minigame = null
	check(g.max_hp == PlayerData.MAX_HP and g.shrink_in == 1, "nothing drops before SHRINK_ROUNDS rounds; the count is at 1")
	g._begin_step(GameController.Step.ROLL)
	check(g.current().hp == PlayerData.MAX_HP, "no HP lost at the start of a turn")
	g._end_round()
	g.minigame = null
	check(g.max_hp == PlayerData.MAX_HP - 1 and g.hand_limit == GameController.HAND_LIMIT - 1,
		"after SHRINK_ROUNDS rounds max HP and the hand limit drop by 1")
	check(g.shrink_in == GameController.SHRINK_ROUNDS, "the count starts again")
	check(p.hp == g.max_hp and q.hand.size() == g.hand_limit, "HP over the new max is lost, extra cards discarded")
	check(g.can_play(p, card("heal_1")) != "", "healing stops at the lowered max")
	g.max_hp = GameController.MIN_MAX_HP
	g.hand_limit = GameController.MIN_HAND_LIMIT
	var before := g.shrink_in
	g._end_round()
	g.minigame = null
	check(not g.shrinking() and g.shrink_in == before and g.max_hp == GameController.MIN_MAX_HP,
		"at the floor nothing more drops")


## The No Items ward: never played by hand, lifts a No Items curse by itself (used up), works
## when bought while cursed, one per hand (shop refuses a second, a drawn second is set aside).
func test_ward() -> void:
	var g := new_game()
	var me := g.players[0]
	var bot := g.players[1]
	me.hand.assign([card(GameController.WARD)])
	check(g.can_play(me, me.hand[0]) != "", "ward: can't be played by hand")
	g._apply(bot, me, "no_items")
	check(not me.has("no_items") and me.find_card(GameController.WARD) < 0, "ward: lifts No Items and is used up")
	g._apply(bot, me, "no_items")
	check(me.has("no_items"), "no ward left: No Items sticks")
	g.turn_index = g.order.find(0)
	g.step = GameController.Step.PHASE1
	g._pause = 0.0
	g.shop[0] = card(GameController.WARD)
	me.gold = 10
	check(g.buy(me, 0) and not me.has("no_items") and me.find_card(GameController.WARD) < 0,
		"ward: bought while cursed, it lifts the curse at once")
	me.hand.assign([card(GameController.WARD)])
	g.shop[1] = card(GameController.WARD)
	check(g.can_buy(me, 1) != "", "ward: only one per hand (shop)")
	g.deck.assign([card("attack"), card(GameController.WARD)])  # the ward is on top
	g._draw(me, 1, false)
	var wards := me.hand.filter(func(c: Dictionary) -> bool: return c["id"] == GameController.WARD).size()
	check(wards == 1 and me.find_card("attack") >= 0, "ward: a second one drawn is set aside for another card")

