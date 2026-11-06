class_name NetPlay
extends Node
## Online play (autoload "Net"; reach it with NetPlay.node()). The player who creates a room is its host: their game runs
## the rules (GameController) for everyone, and each guest's screen mirrors it (GameSync).
## Browsers connect to each other directly (WebRTC); the room API on the same site as the
## game (web/api/room.js on Vercel, tools/dev_server.py locally) only lists the rooms and
## passes the connection offers between them. With RF_NET=enet in the environment, peers
## connect over ENet on this machine instead (tests: tests/net_check.gd).
##
## The lobby lives here too, online or not: `seats` (host order) are the room's places,
## {name, char, human, peer, ready}; seat 0 is the host. Bots fill the free places.

signal lobby_changed
signal chat(bbcode: String)
signal rooms_listed(rooms: Array)
signal room_stats(online: int, playing: int)  # who's around, from the same reply
signal joined  # guest: in the room
signal failed(message: String)  # could not create / join, or the connection was lost
signal game_ready  # host: every guest has the table open; start the game
signal snapshot_ready  # guest: the host's game arrived; start the table

enum Role { OFFLINE, HOST, GUEST }

static var _node: NetPlay


## The online-play node: the autoload, or (scripts run on their own, e.g. tests) a new one.
static func node() -> NetPlay:
	if _node == null or not is_instance_valid(_node):
		var root := (Engine.get_main_loop() as SceneTree).root
		_node = root.get_node_or_null("Net") as NetPlay
		if _node == null:
			_node = NetPlay.new()
			_node.name = "Net"
			root.add_child(_node)
	return _node

const TABLE_SCENE := "res://main.tscn"
const MENU_SCENE := "res://menu.tscn"
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]}
const POLL_MS := 1000
const POLL_IN_GAME_MS := 3000  # host: spectators can still get in; keeps the room listed too
const MAX_WATCHERS := 4
var _who := ""
const CONNECT_TIMEOUT := 20.0
const LOAD_TIMEOUT := 15.0  # host: start without a guest whose table hasn't opened by then
const SNAPSHOT_SECONDS := 0.25  # host: the clocks are re-sent this often
const ENET_PORT := 24680
const WRONG_PASSWORD := "รหัสผ่านไม่ถูกต้อง"
const NEED_PASSWORD := "ห้องนี้ต้องใส่รหัสผ่าน"

var role := Role.OFFLINE
var code := ""  # the room's 6-digit number
var my_seat := 0  # your place in `seats`
var seats: Array = []
var in_game := false
var watching := false  # you: a spectator, not a player

var _peer: MultiplayerPeer
var _rtc: Dictionary = {}  # peer id -> WebRTCPeerConnection
var _poll_at := 0  # by the real clock: a hidden tab's frames run slow
var _polling := false
var _connect_left := -1.0  # guest: seconds left to get through to the host
var _lobby_gen := 0  # bumped when the lobby is rebuilt: old bot timers do nothing
# host, in game
var _game: GameController
var _live := false  # the guests have had the opening state
var _dirty := false
var _snap_left := 0.0
var _loaded: Dictionary = {}  # peer id -> true once their table is open
var _load_left := -1.0
var _logs: Dictionary = {}  # peer id -> log lines kept until the opening state is sent
var _watchers: Dictionary = {}  # peer id -> name: spectators of the game in progress
# guest, in game
var _init_state: Dictionary = {}
var _init_logs: Array = []
var _was_joined := false  # guest: the first lobby from the host has come
var _players_before := 0  # spectator: GameConfig.players to go back to (the table has an extra place)
var _waiting: Dictionary = {}  # browser: request id -> its reply handler
var _next_request := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(func() -> void: _lost("หัวห้องออกจากเกมแล้ว"))


## Rooms with other people work in the browser (WebRTC is built in), or with ENet in tests.
func available() -> bool:
	return OS.has_feature("web") or _enet()


func _enet() -> bool:
	return OS.get_environment("RF_NET") == "enet"


func online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func is_guest() -> bool:
	return role == Role.GUEST


# ---------- the room API (HTTP) ----------

func _api_url() -> String:
	var base := OS.get_environment("RF_API")
	if base == "" and OS.has_feature("web"):
		base = str(JavaScriptBridge.eval("window.location.origin"))
	if base == "":
		base = "http://127.0.0.1:8060"
	return base + "/api/room"


## POST {action, ...} to the room API; `done` gets the JSON reply ({"error": ...} on failure).
func _api(body: Dictionary, done := Callable()) -> void:
	if OS.has_feature("web"):
		_web_fetch(body, done)
		return
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(result: int, status: int, _h: PackedStringArray, data: PackedByteArray) -> void:
		req.queue_free()
		var reply: Variant = null
		if result == HTTPRequest.RESULT_SUCCESS:
			reply = JSON.parse_string(data.get_string_from_utf8())
		if not reply is Dictionary:
			reply = {"error": "network" if result != HTTPRequest.RESULT_SUCCESS else "status %d" % status}
		if done.is_valid():
			done.call(reply))
	var err := req.request(_api_url(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		if done.is_valid():
			done.call({"error": "network"})


## In the browser, through its own fetch(): HTTPRequest there is slow (seconds per request),
## and joining takes a dozen of them. Replies are collected in window.rfReplies and picked up
## each frame (_take_web_replies).
func _web_fetch(body: Dictionary, done: Callable) -> void:
	_next_request += 1
	_waiting[_next_request] = done
	JavaScriptBridge.eval("""(function(){var q=(window.rfReplies=window.rfReplies||[]);
		fetch(%s,{method:'POST',headers:{'Content-Type':'application/json'},body:%s})
		.then(function(r){return r.text();}).then(function(t){q.push([%d,t]);})
		.catch(function(){q.push([%d,'']);});})()""" % [JSON.stringify(_api_url()),
		JSON.stringify(JSON.stringify(body)), _next_request, _next_request])


func _take_web_replies() -> void:
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify((window.rfReplies||[]).splice(0))")
	var list: Variant = JSON.parse_string(str(raw)) if raw != null else null
	if not list is Array:
		return
	for pair: Array in list:
		var id := int(pair[0])
		var reply: Variant = JSON.parse_string(str(pair[1])) if str(pair[1]) != "" else null
		var done: Callable = _waiting.get(id, Callable())
		_waiting.erase(id)
		if done.is_valid():
			done.call(reply if reply is Dictionary else {"error": "network"})


## The minigame questions from the database, for whoever runs the game (guests get each
## question from the host). No reply or a bad one: the questions packed with the game stay.
## Nothing waits for this: the first minigame comes rounds later.
func load_questions() -> void:
	if _enet() or not (OS.has_feature("web") or OS.get_environment("RF_API") != ""):
		return
	_api({"action": "questions"}, func(r: Dictionary) -> void:
		Minigame.use_questions(r.get("questions")))


func list_rooms() -> void:
	if _enet():
		rooms_listed.emit([])
		return
	if _who == "":
		_who = str(randi())  # this browser, so asking again doesn't count it twice
	_api({"action": "list", "who": _who}, func(r: Dictionary) -> void:
		rooms_listed.emit(r.get("rooms", []))
		if r.has("online"):
			room_stats.emit(int(r["online"]), int(r.get("playing", 0))))


# ---------- hosting ----------

## Open the lobby for a new room: you at seat 0, bots in the other places. Online (in the
## browser) the room is also put up for others to find; `done` gets "" or why it couldn't be.
func create_room(my_char: String, done: Callable) -> void:
	leave()
	open_lobby(my_char)
	if not available():
		done.call("")
		return
	if _enet():
		var enet := ENetMultiplayerPeer.new()
		if enet.create_server(ENET_PORT, 6) != OK:
			done.call("เปิดห้องไม่ได้")
			return
		_set_peer(enet)
		role = Role.HOST
		code = "000000"
		done.call("")
		return
	_api({"action": "create", "name": GameConfig.room_name, "max": GameConfig.players,
		"rings": GameConfig.rings_to_win, "preset": GameConfig.preset,
		"password": GameConfig.room_password if GameConfig.room_type == "password" else ""},
		func(r: Dictionary) -> void:
			if r.has("error"):
				done.call("ระบบออนไลน์ไม่พร้อม (%s) · เล่นกับบอทได้ตามปกติ" % r["error"])
				return
			var rtc := WebRTCMultiplayerPeer.new()
			rtc.create_server()
			_set_peer(rtc)
			role = Role.HOST
			code = r["code"]
			GameConfig.room_code = code
			_polling = true
			_poll_at = 0
			done.call(""))


## The lobby, offline or as host: you at seat 0, bots in the other places.
func open_lobby(my_char: String) -> void:
	_lobby_gen += 1
	in_game = false
	my_seat = 0
	if GameConfig.bot_names.size() < GameConfig.players - 1:
		GameConfig.roll_bot_names()
	seats = [{"name": GameConfig.player_name, "char": my_char, "human": true, "peer": 1, "ready": false}]
	for i in range(1, GameConfig.players):
		seats.append(_bot_seat(i))
	_fit_bots()
	_lobby_update()


func _bot_seat(i: int) -> Dictionary:
	var seat := {"name": GameConfig.bot_names[(i - 1) % GameConfig.bot_names.size()], "char": "",
		"human": false, "peer": 0, "ready": false}
	var gen := _lobby_gen
	get_tree().create_timer(randf_range(0.8, 2.6)).timeout.connect(func() -> void:
		if gen == _lobby_gen and i < seats.size() and not seats[i]["human"] and not in_game:
			set_ready(i, true))
	return seat


## Bots take characters nobody has taken (repeats only when there aren't enough).
func _fit_bots() -> void:
	var taken: Array = []
	for s: Dictionary in seats:
		if s["human"]:
			taken.append(s["char"])
	for s: Dictionary in seats:
		if s["human"]:
			continue
		if s["char"] == "" or s["char"] in taken:
			var free := CharacterDB.ids().filter(func(id: String) -> bool: return not id in taken)
			s["char"] = free.pick_random() if not free.is_empty() else CharacterDB.ids().pick_random()
		taken.append(s["char"])


## You changed your name (in Settings).
func rename(new_name: String) -> void:
	if is_guest() or seats.is_empty():
		return
	seats[0]["name"] = new_name
	_lobby_update()


## Seat `i` picks character `id` (taking their Ready back).
func pick(id: String) -> void:
	if is_guest():
		_send(1, {"t": "pick", "char": id})
		return
	_pick(my_seat, id)


func _pick(i: int, id: String) -> void:
	if not CharacterDB.ids().has(id):
		return
	seats[i]["char"] = id
	if seats[i]["ready"]:
		seats[i]["ready"] = false
		_say_system("[color=#e0a070]%s ยกเลิกพร้อม[/color]" % seats[i]["name"])
	_fit_bots()
	_lobby_update()


func set_ready(i: int, on: bool) -> void:
	if is_guest():
		_send(1, {"t": "ready", "on": on})
		return
	if i >= seats.size() or seats[i]["ready"] == on:
		return
	seats[i]["ready"] = on
	_say_system("[color=%s]%s %s[/color]" % ["#7fc97f" if on else "#e0a070", seats[i]["name"],
		"พร้อมแล้ว" if on else "ยกเลิกพร้อม"])
	_lobby_update()


func all_ready() -> bool:
	return seats.all(func(s: Dictionary) -> bool: return s["ready"])


## Send a chat line from you.
func say(text: String) -> void:
	text = text.strip_edges().replace("[", "(")
	if text == "":
		return
	if is_guest():
		_send(1, {"t": "chat", "text": text})
	else:
		_say_from(my_seat, text)


func _say_from(i: int, text: String) -> void:
	_say_system("[color=#ffd76a]%s:[/color] %s" % [seats[i]["name"], text.left(60)])


func _say_system(bbcode: String) -> void:
	chat.emit(bbcode)
	if is_host():
		_broadcast({"t": "chat", "b": bbcode})


## The lobby changed: GameConfig gets the seats (host order), guests get the lobby.
func _lobby_update() -> void:
	_config_from_seats(0)
	lobby_changed.emit()
	if not is_host():
		return
	for id in _guest_ids():
		var seat := _seat_of(id)
		_send(id, {"t": "lobby", "seats": seats, "you": seat, "settings": {
			"room_name": GameConfig.room_name, "players": GameConfig.players,
			"rings_to_win": GameConfig.rings_to_win, "minigames": GameConfig.minigames,
			"turn_seconds": GameConfig.turn_seconds, "preset": GameConfig.preset,
			"start_mode": GameConfig.start_mode}})


## GameConfig.names / characters / humans from the seats, turned so `viewer` is seat 0.
func _config_from_seats(viewer: int) -> void:
	var n := seats.size()
	GameConfig.players = n
	GameConfig.names.clear()
	GameConfig.characters.clear()
	GameConfig.humans.clear()
	for i in n:
		var s: Dictionary = seats[(i + viewer) % n]
		GameConfig.names.append(s["name"])
		GameConfig.characters.append(s["char"])
		GameConfig.humans.append(s["human"])


## Host: everyone is ready; everyone goes to the table.
func start() -> void:
	if is_guest():
		return
	in_game = true
	if is_host():
		_broadcast({"t": "start"})
		_api({"action": "update", "code": code, "status": "playing", "count": _human_count()})
		_loaded.clear()
		_load_left = LOAD_TIMEOUT if not _guest_ids().is_empty() else -1.0
	_config_from_seats(0)


## Host, at the table: call `begin` once every guest's table is open (or after a while).
func when_guests_ready(begin: Callable) -> void:
	if not is_host() or _guest_ids().all(func(id: int) -> bool: return _loaded.has(id)):
		begin.call()
		return
	game_ready.connect(begin, CONNECT_ONE_SHOT)


## Host, back from the results: the same people (and bots) in the lobby, nobody ready.
func back_to_lobby() -> void:
	in_game = false
	_game = null
	_live = false
	_lobby_gen += 1
	for i in seats.size():
		seats[i]["ready"] = false
		if not seats[i]["human"]:
			seats[i] = _bot_seat(i).merged({"char": seats[i]["char"]}, true)
	if is_host():
		_broadcast({"t": "to_lobby"})
		for id: int in _watchers:
			_send(id, {"t": "to_lobby"})
		_watchers.clear()
		_api({"action": "update", "code": code, "status": "open", "count": _human_count()})
		_polling = true
	_lobby_update()


## `wanted`, or "wanted 2", "wanted 3"... if someone in the room already has that name.
func _unique_name(wanted: String) -> String:
	var taken := seats.map(func(s: Dictionary) -> String: return s["name"])
	var name := wanted
	var n := 2
	while name in taken:
		name = "%s %d" % [wanted, n]
		n += 1
	return name


func _human_count() -> int:
	return seats.filter(func(s: Dictionary) -> bool: return s["human"]).size()


# ---------- joining ----------

## Join room `room_code`; `joined` or `failed` follows. With `watch`, as a spectator of the
## game in progress: the table opens by itself, or `failed`.
func join(room_code: String, password := "", watch := false) -> void:
	leave()
	watching = watch
	if _enet():
		var enet := ENetMultiplayerPeer.new()
		if enet.create_client("127.0.0.1", ENET_PORT) != OK:
			failed.emit("เชื่อมต่อไม่ได้")
			return
		_set_peer(enet)
		role = Role.GUEST
		code = room_code
		_connect_left = CONNECT_TIMEOUT
		return
	_api({"action": "join", "code": room_code, "password": password, "watch": watch}, func(r: Dictionary) -> void:
		if r.has("error"):
			watching = false
			failed.emit(_join_error(str(r["error"])))
			return
		role = Role.GUEST
		code = room_code
		var id: int = int(r["peer"])
		var rtc := WebRTCMultiplayerPeer.new()
		_dbg("create_client %d -> %d" % [id, rtc.create_client(id)])
		_set_peer(rtc)
		var conn := _new_connection(1)
		_dbg("create_offer -> %d" % conn.create_offer())
		_polling = true
		_poll_at = 0
		_connect_left = CONNECT_TIMEOUT)


func _join_error(e: String) -> String:
	match e:
		"not_found":
			return "ไม่พบห้องนี้ (เลขห้องผิด หรือห้องปิดไปแล้ว)"
		"full":
			return "ห้องเต็มแล้ว"
		"watchers":
			return "ผู้ชมเต็มแล้ว"
		"over":
			return "เกมนี้จบไปแล้ว"
		"playing":
			return "ห้องนี้กำลังเล่นอยู่"
		"password":
			return WRONG_PASSWORD
	return "เข้าห้องไม่ได้ (%s)" % e


## Leave the room (or close it, as host) and go back to playing on your own.
func leave() -> void:
	if is_host() and not _enet():
		_api({"action": "close", "code": code})
	_polling = false
	_connect_left = -1.0
	if watching and _players_before > 0:
		GameConfig.players = _players_before
		GameConfig.characters.clear()
	watching = false
	_players_before = 0
	_watchers.clear()
	for conn: WebRTCPeerConnection in _rtc.values():
		conn.close()
	_rtc.clear()
	if _peer:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	role = Role.OFFLINE
	code = ""
	my_seat = 0
	in_game = false
	_game = null
	_live = false
	_init_state = {}
	_init_logs.clear()
	_loaded.clear()
	_logs.clear()
	_was_joined = false


func _set_peer(p: MultiplayerPeer) -> void:
	_peer = p
	multiplayer.multiplayer_peer = p


# ---------- WebRTC signalling (through the room API) ----------

func _new_connection(id: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	_dbg("initialize -> %d" % conn.initialize(ICE))
	conn.session_description_created.connect(func(type: String, sdp: String) -> void:
		conn.set_local_description(type, sdp)
		_signal(id, {"t": type, "sdp": sdp}))
	conn.ice_candidate_created.connect(func(media: String, index: int, cname: String) -> void:
		_signal(id, {"t": "ice", "media": media, "index": index, "name": cname}))
	_dbg("add_peer %d -> %d" % [id, (_peer as WebRTCMultiplayerPeer).add_peer(conn, id)])
	_rtc[id] = conn
	return conn


func _signal(to: int, data: Dictionary) -> void:
	_api({"action": "send", "code": code, "to": to, "from": multiplayer.get_unique_id(), "data": data})


func _poll() -> void:
	var body := {"action": "poll", "code": code, "peer": multiplayer.get_unique_id()}
	if is_host():
		body["count"] = _human_count()
		body["watchers"] = _watchers.size()
	_api(body, func(r: Dictionary) -> void:
		if not online():
			return
		if r.get("error") == "not_found" and is_guest() and _connect_left > 0.0:
			_lost("ไม่พบห้องนี้แล้ว")
			return
		for m: Dictionary in r.get("messages", []):
			_on_signal(int(m.get("from", 0)), m.get("data", {})))


func _on_signal(from: int, d: Dictionary) -> void:
	_dbg("signal from %d: %s" % [from, d.get("t")])
	if from <= 0 or not _peer is WebRTCMultiplayerPeer:
		return
	match d.get("t"):
		"offer":  # host: a guest wants in
			if is_host() and not _rtc.has(from):
				_new_connection(from).set_remote_description("offer", d["sdp"])
		"answer":
			if _rtc.has(from):
				_rtc[from].set_remote_description("answer", d["sdp"])
		"ice":
			if _rtc.has(from):
				_rtc[from].add_ice_candidate(d["media"], int(d["index"]), d["name"])


func _process(delta: float) -> void:
	if not _waiting.is_empty():
		_take_web_replies()
	if _polling and not _enet():
		var now := Time.get_ticks_msec()
		if now >= _poll_at:
			_poll_at = now + (POLL_IN_GAME_MS if in_game else POLL_MS)
			_poll()
	if _connect_left > 0.0:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_lost("เชื่อมต่อหัวห้องไม่สำเร็จ · เครือข่ายนี้อาจไม่รองรับ ลองเปลี่ยนเน็ตแล้วเข้าใหม่")
	if _load_left > 0.0:
		_load_left -= delta
		if _load_left <= 0.0:
			_load_left = -1.0
			game_ready.emit()
	if is_host() and _live and _game:
		_snap_left -= delta
		if _dirty or _snap_left <= 0.0:
			_dirty = false
			_snap_left = SNAPSHOT_SECONDS
			for id in _viewer_ids():
				_send(id, {"t": "snap", "s": GameSync.snapshot(_game, _view_of(id))})


# ---------- peers ----------

## Online debugging in the browser: lines collect in window.rfDebug.
func _dbg(line: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(window.rfDebug=window.rfDebug||[]).push(%s)" % JSON.stringify(line))


func _on_peer_connected(id: int) -> void:
	_dbg("peer connected %d" % id)
	if is_guest() and id == 1:
		_connect_left = -1.0
		_polling = false  # through: the API isn't needed any more
		if watching:
			_send(1, {"t": "watch", "name": GameConfig.player_name})
			return
		_send(1, {"t": "join", "name": GameConfig.player_name,
			"char": GameConfig.characters[0] if not GameConfig.characters.is_empty() else ""})


func _on_peer_disconnected(id: int) -> void:
	if is_guest():
		if id == 1:
			_lost("หัวห้องออกจากเกมแล้ว")
		return
	if not is_host():
		return
	_rtc.erase(id)
	if _watchers.has(id):
		_watchers.erase(id)
		return
	var i := _seat_of(id)
	if i < 0:
		return
	var who: String = seats[i]["name"]
	if in_game and _game:
		_game.players[i].is_bot = true  # a bot plays on for them
		_game._log("[color=#e0a070]%s หลุดจากเกม · บอทเล่นแทน[/color]" % who)
		_loaded[id] = true
		if _guest_ids().all(func(g: int) -> bool: return _loaded.has(g)):
			game_ready.emit()
	seats[i] = _bot_seat(i)
	if in_game:
		seats[i]["ready"] = true
	else:
		_say_system("[color=#b9a98a]%s ออกจากห้อง[/color]" % who)
	_fit_bots()
	_lobby_update()


## The connection is gone. Called from inside the network's own callbacks, which must finish
## before the peer is closed (doing it there crashes the game): the rest happens just after.
func _lost(why: String) -> void:
	_lost_now.call_deferred(why)


func _lost_now(why: String) -> void:
	if not online():
		return
	var was_in_game := in_game
	leave()
	failed.emit(why)
	if was_in_game:
		MainMenu.start_screen = "home"
		MainMenu.notice = why
		get_tree().change_scene_to_file(MENU_SCENE)


func _guest_ids() -> Array[int]:
	var out: Array[int] = []
	for s: Dictionary in seats:
		if s["human"] and int(s["peer"]) > 1:
			out.append(int(s["peer"]))
	return out


## Everyone who sees the game: the guests, then the spectators.
func _viewer_ids() -> Array[int]:
	var out := _guest_ids()
	for id: int in _watchers:
		out.append(id)
	return out


## The seat peer `id` sees the game from.
func _view_of(id: int) -> int:
	return GameSync.WATCHER if _watchers.has(id) else _seat_of(id)


func _seat_of(id: int) -> int:
	for i in seats.size():
		if seats[i]["human"] and int(seats[i]["peer"]) == id:
			return i
	return -1


# ---------- messages ----------

func _send(to: int, data: Dictionary) -> void:
	if _peer and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED 			and multiplayer.get_peers().has(to):  # not someone who has just left
		_rx.rpc_id(to, data)


func _broadcast(data: Dictionary) -> void:
	for id in _guest_ids():
		_send(id, data)


@rpc("any_peer", "call_remote", "reliable")
func _rx(d: Dictionary) -> void:
	var from := multiplayer.get_remote_sender_id()
	if is_host():
		_host_rx(from, d)
	elif is_guest() and from == 1:
		_guest_rx(d)


func _host_rx(from: int, d: Dictionary) -> void:
	var i := _seat_of(from)
	match d.get("t"):
		"watch":
			if not in_game or _game == null:
				_send(from, {"t": "refused", "why": "over"})
			elif _watchers.size() >= MAX_WATCHERS:
				_send(from, {"t": "refused", "why": "watchers"})
			else:
				_watchers[from] = str(d.get("name", "ผู้ชม")).left(GameConfig.NAME_MAX)
				if _live:
					_welcome_watcher(from)
		"join":
			if i >= 0 or in_game:
				if in_game and i < 0:
					_send(from, {"t": "refused", "why": "playing"})
				return
			var free := -1
			for k in range(1, seats.size()):
				if not seats[k]["human"]:
					free = k
					break
			if free < 0:
				_send(from, {"t": "refused", "why": "full"})
				return
			var id := str(d.get("char", ""))
			seats[free] = {"name": _unique_name(str(d.get("name", "ผู้เล่น")).left(GameConfig.NAME_MAX)), "human": true, "peer": from, "ready": false,
				"char": id if CharacterDB.ids().has(id) else seats[free]["char"]}
			_say_system("[color=#b9a98a]%s เข้าห้อง[/color]" % seats[free]["name"])
			_fit_bots()
			_lobby_update()
		"pick":
			if i >= 0 and not in_game:
				_pick(i, str(d.get("char", "")))
		"ready":
			if i >= 0 and not in_game:
				set_ready(i, bool(d.get("on", false)))
		"chat":
			if i >= 0:
				_say_from(i, str(d.get("text", "")))
		"loaded":
			if _watchers.has(from):
				return
			_loaded[from] = true
			if _guest_ids().all(func(g: int) -> bool: return _loaded.has(g)):
				_load_left = -1.0
				game_ready.emit()
		"act":
			if i >= 0 and _game and _live:
				_host_action(i, str(d.get("n", "")), d.get("a", []))


func _guest_rx(d: Dictionary) -> void:
	match d.get("t"):
		"lobby":
			seats = d["seats"]
			my_seat = int(d["you"])
			var s: Dictionary = d["settings"]
			GameConfig.room_name = s["room_name"]
			GameConfig.rings_to_win = s["rings_to_win"]
			GameConfig.minigames = s["minigames"]
			GameConfig.turn_seconds = s["turn_seconds"]
			GameConfig.preset = s["preset"]
			GameConfig.start_mode = s["start_mode"]
			_config_from_seats(my_seat)
			var first := not _was_joined
			_was_joined = true
			lobby_changed.emit()
			if first:
				joined.emit()
		"refused":
			_lost(_join_error(str(d.get("why", ""))))
		"watching":  # the game so far: the table opens on it
			var s: Dictionary = d["settings"]
			GameConfig.rings_to_win = s["rings_to_win"]
			GameConfig.minigames = s["minigames"]
			GameConfig.turn_seconds = s["turn_seconds"]
			_players_before = GameConfig.players
			var list: Array = (d["s"] as Dictionary)["players"]
			GameConfig.players = list.size()
			GameConfig.names.assign(list.map(func(p: Dictionary) -> String: return p["name"]))
			GameConfig.characters.assign(list.map(func(p: Dictionary) -> String: return p["character"]))
			GameConfig.humans.assign(list.map(func(p: Dictionary) -> bool: return not p["bot"]))
			in_game = true
			_init_state = d["s"]
			_init_logs = []
			get_tree().change_scene_to_file(TABLE_SCENE)
		"chat":
			chat.emit(d["b"])
		"start":
			in_game = true
			_init_state = {}
			_init_logs.clear()
			_config_from_seats(my_seat)
			get_tree().change_scene_to_file(TABLE_SCENE)
		"to_lobby":  # the host is back in the lobby: "เล่นต่อ" on the results takes you there
			in_game = false
			_game = null
			if watching:  # that game is over: nothing more to watch
				leave.call_deferred()
		"init":
			_init_state = d["s"]
			_init_logs = d.get("log", [])
			snapshot_ready.emit()
		"snap":
			if _game:
				GameSync.apply(_game, d["s"])
				_game.state_changed.emit()
		"ev":
			if _game:
				GameSync.apply(_game, d["s"])
				GameSync.emit_event(_game, d["n"], d["a"])
		"log":
			if _game:
				_game.log_added.emit(d["b"])


# ---------- the game, host side ----------

## Host: the table's game; its events go out to the guests (call before start_game).
func attach_host(g: GameController) -> void:
	_game = g
	_live = false
	_polling = not _enet()  # slowly: spectators still come in through the room API
	_logs.clear()
	g.state_changed.connect(func() -> void: _dirty = true)
	g.log_entry.connect(_on_log_entry)
	for name: String in GameSync.EVENT_SEATS:
		var sig := Signal(g, name)
		var count: int = _signal_arg_count(g, name)
		match count:
			0:
				sig.connect(func() -> void: _on_event(name, []))
			1:
				sig.connect(func(a0: Variant) -> void: _on_event(name, [a0]))
			2:
				sig.connect(func(a0: Variant, a1: Variant) -> void: _on_event(name, [a0, a1]))
			3:
				sig.connect(func(a0: Variant, a1: Variant, a2: Variant) -> void: _on_event(name, [a0, a1, a2]))
			5:
				sig.connect(func(a0: Variant, a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
					_on_event(name, [a0, a1, a2, a3, a4]))


func _signal_arg_count(o: Object, name: String) -> int:
	for s: Dictionary in o.get_signal_list():
		if s["name"] == name:
			return (s["args"] as Array).size()
	return 0


## Host: the game has started; each guest gets it as they see it.
func send_init() -> void:
	for id in _guest_ids():
		_send(id, {"t": "init", "s": GameSync.snapshot(_game, _seat_of(id)), "log": _logs.get(id, [])})
	_logs.clear()
	_live = true
	for id: int in _watchers:
		_welcome_watcher(id)


## Host: spectator `id` gets the game so far.
func _welcome_watcher(id: int) -> void:
	_send(id, {"t": "watching", "s": GameSync.snapshot(_game, GameSync.WATCHER), "settings": {
		"rings_to_win": GameConfig.rings_to_win, "minigames": GameConfig.minigames,
		"turn_seconds": GameConfig.turn_seconds}})
	_game._log("[color=#b9a98a]%s เข้ามาชม[/color]" % _watchers[id])


func _on_event(name: String, args: Array) -> void:
	if not _live:
		return
	var n := _game.players.size()
	for id in _viewer_ids():
		var seat := _view_of(id)
		_send(id, {"t": "ev", "n": name, "a": GameSync.event_args(name, args, seat, n),
			"s": GameSync.snapshot(_game, seat)})


func _on_log_entry(owner: int, text: String, others: String) -> void:
	for id in _viewer_ids():
		var seat := _view_of(id)
		var line := text if owner < 0 or owner == seat else others
		if line == "":
			continue
		if _live:
			_send(id, {"t": "log", "b": line})
		else:
			_logs[id] = _logs.get(id, []) + [line]


## A guest at host seat `i` did something on their screen.
func _host_action(i: int, name: String, a: Array) -> void:
	var g := _game
	var p := g.players[i]
	var n := g.players.size()
	var mine := g.current() == p
	match name:
		"advance":
			if mine:
				g.advance()
		"play_card":
			if mine and a.size() == 2:
				g.play_card(p, int(a[0]), GameSync.from_view(int(a[1]), i, n))
		"buy":
			if mine and a.size() == 2:
				g.buy(p, int(a[0]), int(a[1]))
		"exchange_ring":
			if mine:
				g.exchange_ring(p)
		"respond_defense":
			if not g.pending_attack.is_empty() and int(g.pending_attack["target"]) == i and a.size() == 1:
				g.respond_defense(bool(a[0]))
		"minigame_answer":
			if a.size() == 1:
				g.minigame_answer(p, str(a[0]))


# ---------- the game, guest side ----------

## Guest: the table's game becomes a mirror of the host's. `begin` runs once the host's game
## has arrived (the table is then set up from it).
func attach_guest(g: GameController, begin: Callable) -> void:
	_game = g
	g.remote = func(name: String, args: Array) -> void: _send(1, {"t": "act", "n": name, "a": args})
	var go := func() -> void:
		GameSync.apply(g, _init_state)
		begin.call()
		for line: String in _init_logs:
			g.log_added.emit(line)
		_init_logs.clear()
	if not _init_state.is_empty():
		go.call()
	else:
		snapshot_ready.connect(go, CONNECT_ONE_SHOT)
	_send(1, {"t": "loaded"})
