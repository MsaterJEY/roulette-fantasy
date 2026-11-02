class_name Sfx
extends Node
## Plays the few sound effects in assets/sounds (.wav or .ogg; replace a file to change a
## sound; sources and licences in docs/design.md). A small pool of players so sounds can
## overlap; play() can wait `delay` seconds first, to line up with an animation.
## Silent in headless runs (tests): no audio there, and quitting mid-sound leaks at exit.

const DIR := "res://assets/sounds/"
const VOICES := 6

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _enabled := true


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	# closing the window mid-sound would leave the playback behind at exit: stop first
	get_tree().auto_accept_quit = false
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Play `sound` (file name without .wav) after `delay` seconds, `volume_db` louder/quieter.
func play(sound: String, delay := 0.0, volume_db := 0.0) -> void:
	if not _enabled:
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(play.bind(sound, 0.0, volume_db))
		return
	var stream := _stream(sound)
	if stream == null:
		return
	var player := _players[0]
	for p in _players:  # a free voice, or else the one that has played longest
		if not p.playing:
			player = p
			break
		if p.get_playback_position() > player.get_playback_position():
			player = p
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Quit the game cleanly: silence everything, let the mixer let go, then quit.
func quit() -> void:
	for p in _players:
		p.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		_streams[sound] = null
		for ext: String in [".wav", ".ogg"]:
			if ResourceLoader.exists(DIR + sound + ext):
				_streams[sound] = load(DIR + sound + ext)
				break
			# a file just picked in the sound lab and not imported yet: read it directly
			var raw := ProjectSettings.globalize_path(DIR + sound + ext)
			if FileAccess.file_exists(raw):
				_streams[sound] = AudioStreamOggVorbis.load_from_file(raw) if ext == ".ogg" 					else AudioStreamWAV.load_from_file(raw)
				break
	return _streams[sound]


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	_streams.clear()
