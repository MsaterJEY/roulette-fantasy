extends SceneTree
## Screenshot helper for the menus. Run with --write-movie and user args:
## home, find, join, settings,
## create (add `custom` for every setting open, `password` for a password room,
## `nominigame` for minigames and rings off),
## lobby (add a number for the players, e.g. `lobby 3`; `auto` for an auto-start room;
## `ready` to press Ready), howto (add a page number, e.g. `howto 7`).
## SHOT_FRAMES (environment) sets how many frames to run (default 40).

var menu: MainMenu
var frames := 0
var args := OS.get_cmdline_user_args()


func _initialize() -> void:
	var screen: String = args[0] if args.size() > 0 else "home"
	if screen == "lobby":
		GameConfig.players = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 4
		GameConfig.start_mode = "auto" if "auto" in args else "host"
		GameConfig.new_room_code()
	if "nominigame" in args:
		GameConfig.minigames = false
		GameConfig.rings_to_win = 0
	if "password" in args:
		GameConfig.room_type = "password"
		GameConfig.new_room_password()
	MainMenu.start_screen = screen if screen in ["home", "find", "join", "create", "lobby"] else "home"
	menu = load("res://menu.tscn").instantiate()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_open(args[0] if args.size() > 0 else "home")
	return frames > int(OS.get_environment("SHOT_FRAMES") if OS.get_environment("SHOT_FRAMES") != "" else "40")


func _open(screen: String) -> void:
	if screen == "settings":
		menu._open_settings()
	elif screen == "howto":
		menu._open_howto(int(args[1]) - 1 if args.size() > 1 else 0)
	elif screen == "join":
		menu.toast("กำลังเชื่อมต่อห้อง 123456...")
	elif screen == "create" and "custom" in args:
		if "nominigame" in args:  # show the rules and minigame sections instead of the room one
			menu._open_sections["rules"] = true
			menu._open_sections["minigame"] = true
			menu._choose_preset("custom")
			menu._open_sections["room"] = false
			menu._fill_sections()
		else:
			menu._choose_preset("custom")
	elif screen == "lobby" and "ready" in args:
		NetPlay.node().set_ready(0, true)
