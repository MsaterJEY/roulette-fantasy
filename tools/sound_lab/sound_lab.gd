extends SceneTree
## Sound lab: listen to the candidate sounds for each slot and pick one. Run:
##   Godot.exe --path . -s res://tools/sound_lab/sound_lab.gd
## ▶ plays a candidate, the round button picks it ("ไม่ใส่เสียง" = silent), "บันทึก" copies
## each pick into assets/sounds/<slot>.wav|ogg (what the game plays; a silent slot has no
## file) and remembers the picks in choices.json.
## Candidates (CC0, sources in candidates.json) are in tools/sound_lab/candidates.

const DIR := "res://tools/sound_lab/candidates/"
const CHOICES := "res://tools/sound_lab/choices.json"
const SOUNDS := "res://assets/sounds/"
const SLOTS := {
	"select": "เสียงกดเลือกตัวละคร",
	"confirm": "เสียงยืนยันการเลือกตัวละคร (ปุ่มเริ่มเกม)",
	"sword": "เสียงฟันดาบ",
	"bow": "เสียงยิงธนู",
	"dice": "เสียงทอยลูกเต๋า",
	"claw": "มังกรตะปบ (ท่าโจมตีปกติของมังกร)",
	"dragon_roar": "มังกรคำราม (ก่อนพ่นไฟ ท่าสังหาร)",
	"dragon_fire": "มังกรพ่นไฟ (ท่าสังหาร)",
	"burning": "ไฟลุกบนตัวคนที่โดนพ่นไฟ",
	"magic_wave": "คลื่นเวทของอัศวิน (ท่าโจมตีปกติ)",
	"verdict": "อัศวินฟาดดาบยักษ์ลงมา (ท่าสังหาร)",
	"burst": "ร่างระเบิด (ท่าสังหารของนักล่าอาคม)",
	"arrow_pin": "ลูกศรยักษ์ปักโต๊ะ (ท่าสังหารของเรนเจอร์)",
	"hurt": "โดนโจมตี (เสียเลือด)",
	"block": "ป้องกันได้ (โล่)",
	"card_play": "ใช้การ์ด (ที่ไม่ใช่การ์ดโจมตี)",
	"coin": "ซื้อของในร้าน",
	"turn": "ถึงตาคุณ",
	"win": "ชนะ",
	"lose": "แพ้",
}

var player := AudioStreamPlayer.new()
var picks: Dictionary = {}  # slot -> candidate file name
var status: Label


func _initialize() -> void:
	var ui := Control.new()
	ui.theme = UiStyle.make_theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	root.add_child(player)
	var bg := ColorRect.new()
	bg.color = UiStyle.WOOD_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	ui.add_child(outer)
	var title := Label.new()
	title.text = "  ห้องทดลองเสียง · กด ▶ เพื่อฟัง แล้วกดวงกลมเลือกอันที่ชอบ จากนั้นกด \"บันทึก\""
	title.add_theme_color_override("font_color", UiStyle.ACTIVE)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var cands: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "candidates.json"))
	if FileAccess.file_exists(CHOICES):
		picks = JSON.parse_string(FileAccess.get_file_as_string(CHOICES))
	for slot: String in SLOTS:
		var head := Label.new()
		head.text = "  " + SLOTS[slot]
		head.add_theme_font_size_override("font_size", 17)
		head.add_theme_color_override("font_color", UiStyle.BRASS)
		list.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		list.add_child(grid)
		var group := ButtonGroup.new()
		var none := CheckBox.new()  # a silent slot
		none.text = "— ไม่ใส่เสียง —"
		none.button_group = group
		none.button_pressed = picks.get(slot, "") == ""
		none.toggled.connect(func(on: bool) -> void:
			if on:
				picks[slot] = ""
				player.stop())
		grid.add_child(none)
		for c: Dictionary in cands.get(slot, []):
			var row := HBoxContainer.new()
			row.custom_minimum_size = Vector2(300, 0)
			grid.add_child(row)
			var pick := CheckBox.new()
			pick.button_group = group
			pick.button_pressed = picks.get(slot, "") == c["file"]
			pick.toggled.connect(func(on: bool) -> void:
				if on:
					picks[slot] = c["file"]
					_play(slot, c["file"]))
			row.add_child(pick)
			var play := Button.new()
			play.text = "▶ " + c["label"]
			play.alignment = HORIZONTAL_ALIGNMENT_LEFT
			play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			play.pressed.connect(_play.bind(slot, c["file"]))
			row.add_child(play)

	var bottom := HBoxContainer.new()
	outer.add_child(bottom)
	var save := Button.new()
	save.text = "  บันทึกเสียงที่เลือก  "
	save.custom_minimum_size = Vector2(0, 40)
	save.pressed.connect(_save)
	bottom.add_child(save)
	status = Label.new()
	status.text = "  ยังไม่ได้บันทึก"
	bottom.add_child(status)


func _play(slot: String, file: String) -> void:
	var path := ProjectSettings.globalize_path(DIR + slot + "/" + file)
	player.stop()
	player.stream = AudioStreamOggVorbis.load_from_file(path) if file.ends_with(".ogg") \
		else AudioStreamWAV.load_from_file(path)
	player.play()


func _save() -> void:
	var done := PackedStringArray()
	for slot: String in SLOTS:
		var file: String = picks.get(slot, "")
		for old: String in ["wav", "ogg"]:  # one file per slot (none when silent)
			for p: String in [SOUNDS + slot + "." + old, SOUNDS + slot + "." + old + ".import"]:
				if FileAccess.file_exists(ProjectSettings.globalize_path(p)):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		if file == "":
			continue
		DirAccess.copy_absolute(ProjectSettings.globalize_path(DIR + slot + "/" + file),
			ProjectSettings.globalize_path(SOUNDS + slot + "." + file.get_extension()))
		done.append(SLOTS[slot].replace("เสียง", "").get_slice(" (", 0))
	var f := FileAccess.open(CHOICES, FileAccess.WRITE)
	f.store_string(JSON.stringify(picks, " "))
	f.close()
	status.text = "  บันทึกแล้ว %d เสียง · ปิดหน้าต่างได้เลย" % done.size()
