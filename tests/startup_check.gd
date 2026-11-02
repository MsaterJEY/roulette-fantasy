extends SceneTree
## Starts the real table with several random seeds (some put the human first) and
## lets each run a few frames. Run without --headless so the human seat is live:
##   Godot_console.exe --path . -s res://tests/startup_check.gd --write-movie <tmp>/f.png
## Script errors show up in the output.

var seeds := [1, 2, 3, 4, 5, 6, 7, 8]
var table: Node
var frames := 0
var human_first := 0


func _process(_delta: float) -> bool:
	if frames % 10 == 0:
		if table:
			table.queue_free()
		if seeds.is_empty():
			print("STARTUP OK, human went first in %d run(s)" % human_first)
			return true
		seed(seeds.pop_front())
		table = load("res://main.tscn").instantiate()
		table.auto_pick = "random"  # skip the character screen
		root.add_child(table)
		if table.game.current().seat == 0:
			human_first += 1
	frames += 1
	return false
