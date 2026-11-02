class_name CharacterDB
extends RefCounted
## Playable characters from data/characters.json (name, weapon = Attack card name, move
## names, animation style, weapon icon).

const PATH := "res://data/characters.json"

static var _all: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _all.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not (parsed is Dictionary and parsed.get("characters") is Array):
			push_error("cannot read %s" % PATH)
			return _all
		for c: Dictionary in parsed["characters"]:
			_all.append(c)
	return _all


static func get_character(id: String) -> Dictionary:
	for c in all():
		if c["id"] == id:
			return c
	return {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for c in all():
		out.append(c["id"])
	return out
