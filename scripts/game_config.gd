class_name GameConfig
extends RefCounted
## What the menus decide and the table plays with: the room settings, who sits where with
## which character, and the player's own settings (kept in user://settings.cfg).

const SETTINGS := "user://settings.cfg"

# room (Create Room). Anyone may pick a character someone else has (the bots still spread
# over the others first, for variety).
static var room_name := "ห้องของฉัน"
static var room_code := ""
static var players := 4  # 2-6, you and bots
static var rings_to_win := 5  # 0 = rings off: the last player standing wins
static var turn_seconds := 20  # each phase of a turn
static var minigames := true  # a minigame every 2 rounds (its shards are the only way to rings)
static var room_type := "public"  # "public" or "password" (takes effect with online play)
static var room_password := ""  # 4 digits, for a "password" room
static var start_mode := "host"  # "host": the host presses Start once everyone is ready; "auto": starts itself
static var preset := "standard"

## Ready-made rooms: a few clicks for most players; "custom" opens every setting.
const PRESETS := {
	"standard": {"name": "ห้องมาตรฐาน", "desc": "4 คน · 5 วง · 20 วิ", "icon": "ring",
		"players": 4, "rings_to_win": 5, "turn_seconds": 20, "start_mode": "host", "minigames": true},
	"quick": {"name": "เล่นเร็ว", "desc": "3 คน · 3 วง · 15 วิ", "icon": "turn",
		"players": 3, "rings_to_win": 3, "turn_seconds": 15, "start_mode": "auto", "minigames": true},
	"chaos": {"name": "สายปั่น", "desc": "4 คน · 7 วง · 30 วิ", "icon": "bad_luck",
		"players": 4, "rings_to_win": 7, "turn_seconds": 30, "start_mode": "host", "minigames": true},
	"custom": {"name": "กำหนดเอง", "desc": "ปรับเองทุกอย่าง", "icon": "shop"},
}

# seats, set in the lobby: character id per seat (0 = you) and display names
static var characters: Array[String] = []
static var names: Array[String] = []
static var humans: Array[bool] = []  # seats played by people (online); empty = you only

# player settings
const NAME_MAX := 24  # characters; Thai vowels and tone marks each count as one
static var player_name := "ผู้เล่น"
static var sfx_volume := 0.8  # 0..1
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		player_name = cfg.get_value("player", "name", player_name)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	apply_volume()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS)
	apply_volume()


static func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(0, sfx_volume <= 0.001)


static func apply_preset(id: String) -> void:
	preset = id
	var p: Dictionary = PRESETS[id]
	players = p.get("players", players)
	rings_to_win = p.get("rings_to_win", rings_to_win)
	turn_seconds = p.get("turn_seconds", turn_seconds)
	start_mode = p.get("start_mode", start_mode)
	minigames = p.get("minigames", minigames)


static func new_room_password() -> void:
	room_password = "%04d" % randi_range(0, 9999)


static func new_room_code() -> void:
	room_code = "%06d" % randi_range(100000, 999999)


## Names the bots get at random (a new draw for each new room).
const BOT_NAMES := ["อัลดริก", "เซเลน่า", "บอร์ก", "ไลร่า", "คาเอล", "มิร่า", "ธอร์น", "อีวา",
	"กาเร็ธ", "นีน่า", "ร็อค", "ลูน่า", "วาเลน", "ฟินน์", "ไอริส", "ดราโก้", "เฟรย่า", "โอเว่น",
	"ซาร่า", "เคล", "โรวัน", "ทาเลีย", "บรัม", "เอลวิน"]

static var bot_names: Array[String] = []  # this room's bots, by seat - 1


## Draw fresh bot names (never the player's own name, no two alike).
static func roll_bot_names() -> void:
	var pool: Array = BOT_NAMES.filter(func(n: String) -> bool: return n != player_name)
	pool.shuffle()
	bot_names.assign(pool.slice(0, 5))


## Seat the bots for `my_id`: other characters first (random), repeats only when there
## aren't enough to go round. You are called by your own name; the bots keep this room's
## random names (bot_names) even when you change character.
static func fill_seats(my_id: String) -> void:
	var ids := CharacterDB.ids()
	var others := ids.filter(func(id: String) -> bool: return id != my_id)
	others.shuffle()
	characters = [my_id]
	for i in range(1, players):
		if i - 1 < others.size():
			characters.append(others[i - 1])
		else:
			characters.append(ids.pick_random())
	if bot_names.size() < players - 1:
		roll_bot_names()
	names = [player_name]
	for i in range(1, players):
		names.append(bot_names[i - 1])
