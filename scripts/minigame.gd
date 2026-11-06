class_name Minigame
extends RefCounted
## "Guess the rank": one question from data/minigame_ranks.json, ROUNDS rounds; in each
## round every living player names one item in turn order. Score = 101 − rank (not in the
## list = 0). Nobody may repeat an answer already given. Pure rules, no UI.

const PATH := "res://data/minigame_ranks.json"
const ROUNDS := 3
const ANSWER_SECONDS := 15.0
## [shards, gold] by place (1st, 2nd, 3rd, 4th)
const REWARDS := [[3, 10], [2, 5], [1, 5], [0, 3]]

static var _questions: Array[Dictionary] = []

var question: Dictionary  # {"question": text, "items": [{"name", "aliases"}]}
var seats: Array[int] = []  # answering order (living players)
var round_no := 1
var turn := 0  # index into seats
var time_left := ANSWER_SECONDS
## Every answer so far: {"seat", "round", "text", "rank" (0 = not in list), "points"}
var answers: Array[Dictionary] = []
var scores: Dictionary = {}  # seat -> points
var used: Dictionary = {}  # item index -> true once someone named it


static func questions() -> Array[Dictionary]:
	if _questions.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not (parsed is Dictionary and parsed.get("questions") is Array):
			push_error("cannot read %s" % PATH)
			return _questions
		for q: Dictionary in parsed["questions"]:
			_questions.append(q)
	return _questions


## Use `list` (from the database) instead of the questions packed with the game. Bad entries
## are dropped; with nothing usable the current questions stay. Returns whether it was used.
static func use_questions(list: Variant) -> bool:
	if not list is Array:
		return false
	var good: Array[Dictionary] = []
	for q: Variant in list:
		if _usable(q):
			good.append(q)
	if good.is_empty():
		return false
	_questions = good
	return true


static func _usable(q: Variant) -> bool:
	if not (q is Dictionary and q.get("question") is String and q["question"] != ""):
		return false
	if not (q.get("items") is Array and not q["items"].is_empty()):
		return false
	for item: Variant in q["items"]:
		if not (item is Dictionary and item.get("name") is String and item["name"] != ""):
			return false
		var aliases: Variant = item.get("aliases", [])
		if not (aliases is Array and aliases.all(func(a: Variant) -> bool: return a is String)):
			return false
	return true


func _init(p_question: Dictionary, p_seats: Array[int]) -> void:
	question = p_question
	seats = p_seats
	for s in seats:
		scores[s] = 0


func current_seat() -> int:
	return seats[turn]


func done() -> bool:
	return round_no > ROUNDS


static func normalize(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "").replace(".", "")


## Index of the item `text` names (by name or alias), or -1.
func find_item(text: String) -> int:
	var key := normalize(text)
	if key == "":
		return -1
	var items: Array = question["items"]
	for i in items.size():
		var item: Dictionary = items[i]
		if normalize(item["name"]) == key:
			return i
		for alias: String in item.get("aliases", []):
			if normalize(alias) == key:
				return i
	return -1


## Why `text` cannot be accepted, or "" if it can (empty text = pass, always accepted).
func check_answer(text: String) -> String:
	if normalize(text) == "":
		return ""
	var i := find_item(text)
	if i >= 0 and used.has(i):
		return "มีคนตอบ %s ไปแล้ว" % question["items"][i]["name"]
	for a in answers:
		if normalize(a["text"]) == normalize(text):
			return "มีคนตอบคำนี้ไปแล้ว"
	return ""


## Record the current player's answer and move on. Returns the answer entry, or {} if the
## answer is not allowed (see check_answer).
func submit(text: String) -> Dictionary:
	if done() or check_answer(text) != "":
		return {}
	var i := find_item(text)
	var rank := i + 1 if i >= 0 else 0
	var points := 101 - rank if rank > 0 else 0
	if i >= 0:
		used[i] = true
	var entry := {"seat": current_seat(), "round": round_no,
		"text": question["items"][i]["name"] if i >= 0 else text.strip_edges(),
		"rank": rank, "points": points}
	answers.append(entry)
	scores[current_seat()] += points
	turn += 1
	if turn >= seats.size():
		turn = 0
		round_no += 1
	time_left = ANSWER_SECONDS
	return entry


## Final standings: [{"seat", "score", "place", "shards", "gold"}], best first.
## Equal scores share the place (and its reward).
func results() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in seats:
		var higher := seats.filter(func(o: int) -> bool: return scores[o] > scores[s]).size()
		var reward: Array = REWARDS[mini(higher, REWARDS.size() - 1)]
		out.append({"seat": s, "score": scores[s], "place": higher + 1, "shards": reward[0], "gold": reward[1]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return out
