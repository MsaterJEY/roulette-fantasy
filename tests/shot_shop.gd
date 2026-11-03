extends SceneTree
## Screenshot helper: opens the table, puts you in Preparation with the shop open.
## Run with --write-movie to capture frames. Add `-- noshop` to leave the shop closed,
## `-- toast` to show the "your turn" text instead of the shop, `-- hint` for why a clicked card can't be played, `-- roll` to throw the dice,
## `-- fx` for a full hand (one card lifted) plus a blocked and a landed attack.
## `-- throw` for thrown cards and a hurt face, `-- target` for picking an attack target (bots glow, history open), `-- self` / `-- selfblind` for effects on you (hit / block while blind), `-- replace` for buying with a full hand (pick a card to swap out), `-- minigame` for the minigame on your turn (a few answers in), `-- result` for the end screen, `-- defend` for the defense prompt when a bot attacks you, `-- dicetip` for the dice scoring tip.

var table: Node
var frames := 0


func _initialize() -> void:
	table = load("res://main.tscn").instantiate()
	table.auto_pick = "random"  # skip the character screen
	root.add_child(table)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		var g: GameController = table.game
		g._opening = 0.0  # straight into a turn
		g.turn_index = g.order.find(0)
		g._pause = 0.0
		g.players[0].gold = 7
		g.players[0].shards = 4
		g.players[0].statuses = {"truce": 2, "free_block": 2}
		g.players[1].statuses = {"blind": 1, "bad_luck": 1}
		g.players[2].statuses = {"no_items": 1}
		g.players[3].statuses = {"truce": 2, "no_shop": 1, "free_block": 1}
		g.step = GameController.Step.PHASE1
		g.time_left = 13.0  # bar about two-thirds full
		g.state_changed.emit()
		var args := OS.get_cmdline_user_args()
		if "fx" in args:
			var me := g.players[0]
			me.hand.clear()
			for id in ["attack", "defense", "heal_1", "gain_defense", "truce", "blind", "cleanse_all"]:
				me.hand.append(CardDB.get_card(id))
			g.state_changed.emit()
			var b: Button = table.hand_box.get_child(2)
			table._lift(b, true, 2)
			g.attacked.emit(0, 1, true)
			g.attacked.emit(0, 2, false)
		elif "roll" in args:
			g.step = GameController.Step.ROLL
			g.roll_dice()
		elif "throw" in args:
			# you throw an Attack at bot B (no defense), bot C throws a curse at bot A
			var me := g.players[0]
			me.hand.assign([CardDB.get_card("attack")])
			for p in g.players:
				p.statuses.clear()
			g.players[2].hand.clear()
			g.step = GameController.Step.PHASE2
			g.state_changed.emit()
			g.play_card(me, 0, 2)
			g.card_played.emit(3, 1, CardDB.get_card("blind"))
		elif "target" in args:
			# picking an attack target: bots glow, the mouse is over bot A
			var me := g.players[0]
			me.hand.clear()
			me.hand.append(CardDB.get_card("attack"))
			me.statuses.clear()
			for p in g.players:
				if p.seat != 0:
					p.statuses.clear()
			g.step = GameController.Step.PHASE2
			g.state_changed.emit()
			table._on_card_pressed(0)
			table.tavern.set_hover(1)
			table.log_tab.pressed.emit()
		elif "self" in args or "selfblind" in args:
			var me := g.players[0]
			me.hand.clear()
			for id in ["attack", "defense", "heal_1", "ward_no_items", "no_shop", "blind"]:
				me.hand.append(CardDB.get_card(id))
			if "selfblind" in args:
				me.statuses = {"blind": 2}
				g.state_changed.emit()
				g.attacked.emit(1, 0, true)
			else:
				me.statuses = {"no_items": 1, "no_shop": 2, "truce": 2}
				g.step = GameController.Step.PHASE1
				g.state_changed.emit()
				g.attacked.emit(1, 0, false)
		elif "replace" in args:
			var me := g.players[0]
			me.hand.clear()
			for id in ["heal_1", "cleanse_1", "defense", "defense", "defense", "attack", "defense"]:
				me.hand.append(CardDB.get_card(id))
			table.shop_panel.visible = true
			table._replacing = 0
			g.state_changed.emit()
			table._fill_shop()
		elif "minigame" in args:
			g.minigames_played = 0
			g.order.assign([0, 1, 2, 3])
			g._start_minigame()
			g.minigame.turn = 1  # bots A–C answer round 1, then it's your turn in round 2
			for text: String in ["", g.minigame.question["items"][2]["name"], "ลาว"]:
				g.minigame.submit(text)
			g.minigame.time_left = 11.4
			g.minigame_changed.emit()
		elif "result" in args:
			g.players[1].rings = 5
			g.players[1].kills = 1
			g.players[1].damage = 6
			g.players[0].damage = 3
			g.players[0].helps = 2
			g.players[3].alive = false
			g.players[3].hp = 0
			g.round_no = 14
			g.minigames_played = 6
			g._finish(g.players[1], "สะสมแหวนครบ 5 วง")
		elif "defend" in args:
			# a bot attacks you: the "use a Defense card?" prompt
			var me := g.players[0]
			me.hand.clear()
			for id in ["defense", "attack", "heal_1"]:
				me.hand.append(CardDB.get_card(id))
			me.statuses.clear()
			g.state_changed.emit()
			g.attack_incoming.emit(1, 0)
		elif "dicetip" in args:
			table.dice_tip.visible = true
		elif "toast" in args:
			g.turn_started.emit(0)
		elif "hint" in args:  # a card clicked that can't be played yet
			table._flash_hint("การ์ดนี้ใช้ได้ในช่วง Combat (ต่อสู้)")
		elif not "noshop" in args:
			table.shop_panel.visible = true
			table._fill_shop()
	var args := OS.get_cmdline_user_args()
	return frames > (60 if "roll" in args or "throw" in args else (330 if "result" in args else 20))
