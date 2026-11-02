extends SceneTree
## Records a character attack for screenshots. Run with --write-movie and user args:
##   -- <style> [finish] [you | side]
## style: blood / arcane / thorn / flame. A bot with that style attacks another bot (or you
## with "you"); "finish" makes it the knockout hit, so the finisher plays.

var table: Node
var frames := 0
var args := OS.get_cmdline_user_args()


func _initialize() -> void:
	table = load("res://main.tscn").instantiate()
	# you get a character without that style, so a bot has it
	var style: String = args[0] if not args.is_empty() else "blood"
	for c in CharacterDB.all():
		if c["style"] != style:
			table.auto_pick = c["id"]
			break
	root.add_child(table)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		var g: GameController = table.game
		g._opening = 0.0
		g.autoplay = false
		var style: String = args[0] if not args.is_empty() else "blood"
		var attacker := -1
		for p in g.players:
			if CharacterDB.get_character(p.character).get("style") == style:
				attacker = p.seat
		var target := 0 if "you" in args else (2 if attacker != 2 else 1)
		if "side" in args:  # a bot on the left or right, seen more from the side
			target = 3 if attacker != 3 else 1
		var a := g.players[attacker]
		var t := g.players[target]
		for p in g.players:
			p.statuses.clear()
		t.hand.assign([CardDB.get_card("heal_1"), CardDB.get_card("cleanse_1"), CardDB.get_card("blind")])  # no Defense
		t.hp = 1 if "finish" in args else PlayerData.MAX_HP
		a.hand.assign([CardDB.get_card("attack")])
		g.turn_index = g.order.find(attacker)
		g.step = GameController.Step.PHASE2
		g._pause = 0.0
		g.state_changed.emit()
		g.play_card(a, 0, target)
	return frames > (330 if "you" in args else 170)  # yours: the camera also glides back
