extends SceneTree
## Screenshot helper: the character select screen, as a new game opens it. Add `hover` to
## point at the second character. Run with --write-movie.

var frames := 0
var table: Node


func _initialize() -> void:
	table = load("res://main.tscn").instantiate()
	root.add_child(table)


func _process(_delta: float) -> bool:
	frames += 1
	return frames > 40
