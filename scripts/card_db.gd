class_name CardDB
extends RefCounted
## Card definitions from data/cards.json, and a freshly shuffled draw pile.

const PATH := "res://data/cards.json"

static var _cards: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _cards.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not (parsed is Dictionary and parsed.get("cards") is Array):
			push_error("cannot read %s" % PATH)
			return _cards
		for c: Dictionary in parsed["cards"]:
			_cards.append(c)
	return _cards


static func get_card(id: String) -> Dictionary:
	for c in all():
		if c["id"] == id:
			return c
	push_error("unknown card id %s" % id)
	return {}


static func make_deck(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	for c in all():
		for i in int(c.get("count", 1)):
			deck.append(c)
	shuffle(deck, rng)
	return deck


static func shuffle(cards: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
