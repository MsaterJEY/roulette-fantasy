class_name PlayerData
extends RefCounted
## One seat at the table: resources, hand and status. Pure data, no UI.

const MAX_HP := 4  # balance sim: 5 meant almost nobody was knocked out
const RINGS_TO_WIN := 5

var seat: int
var display_name: String
var is_bot: bool
## Character id (data/characters.json): looks, the Attack card's name and the attack moves.
var character := ""
var hp: int = MAX_HP
var gold: int = 2
var shards: int = 0
var rings: int = 0
var hand: Array[Dictionary] = []  # card dicts from CardDB
var alive: bool = true
# for the results screen
var kills := 0  # players this one knocked out
var damage := 0  # HP taken off others
var helps := 0  # help cards played
## Active effects: id -> turns left (counted down at the end of this player's own turn).
## Curses: no_items, no_shop, bad_luck (until the next roll), blind. Good effects: truce,
## free_block (value = free blocks left; lasts until used).
var statuses: Dictionary = {}


func _init(p_seat: int, p_name: String, p_is_bot: bool) -> void:
	seat = p_seat
	display_name = p_name
	is_bot = p_is_bot


func has(status: String) -> bool:
	return statuses.has(status)


func find_card(id: String) -> int:
	for i in hand.size():
		if hand[i]["id"] == id:
			return i
	return -1


## Up to `cap` (the game's max HP, which drops every few rounds).
func heal(n: int, cap := MAX_HP) -> void:
	hp = mini(cap, hp + n)

