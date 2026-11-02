extends SceneTree
## Bot sanity check: plays bot-only games and reports every heal/defense/cleanse card
## a bot plays together with its HP and hand just before the effect. Headless:
##   Godot_console.exe --headless --path . -s res://tests/bot_check.gd

class Probe:
	extends GameController
	var wasted := 0
	var used := 0
	var overheal := 0  # heal points lost to the HP cap

	func _apply(p: PlayerData, t: PlayerData, id: String) -> void:
		if id in ["heal_1", "heal_2", "gain_defense", "cleanse_1", "cleanse_all"]:
			used += 1
			var hp_full := p.hp >= PlayerData.MAX_HP
			var waste := id.begins_with("heal") and hp_full
			if id.begins_with("heal"):
				overheal += maxi(0, p.hp + (1 if id == "heal_1" else 2) - PlayerData.MAX_HP)
			if waste:
				wasted += 1
			print("%s %-12s hp %d/5 defense cards %d effects %s%s" % [p.display_name, id, p.hp, BotBrain._count(p, "defense"),
				p.statuses.keys(), "   <-- WASTED" if waste else ""])
		super(p, t, id)


var g: Probe
var frames := 0


func _initialize() -> void:
	g = Probe.new()
	g.autoplay = true
	g.speed = 40.0
	root.add_child(g)
	g.start_game(["คุณ", "บอท A", "บอท B", "บอท C"])


func _process(_delta: float) -> bool:
	frames += 1
	if frames >= 3000 or g.finished:
		print("BOTCHECK used %d help cards, wasted %d, overheal %d (rounds %d)" % [g.used, g.wasted, g.overheal, g.round_no])
		return true
	return false
