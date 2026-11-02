class_name PixelTex
extends RefCounted
## Tiny placeholder textures made in code (wood planks, bricks, felt, banner, glow ring,
## die faces). Low resolution on purpose: the 3D view is drawn with nearest filtering.


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _noise(rng: RandomNumberGenerator, c: Color, amount: float) -> Color:
	var k := rng.randf_range(-amount, amount)
	return Color(c.r + k, c.g + k, c.b + k)


static func planks(light: Color, dark: Color) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var c := _noise(rng, light, 0.03)
			if y % 8 == 0 or (x + (y / 8) * 11) % 32 == 0:
				c = dark
			img.set_pixel(x, y, c)
	return _tex(img)


static func bricks(light: Color, dark: Color) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var row := y / 8
			var c := _noise(rng, light, 0.04)
			if y % 8 == 7 or (x + (8 if row % 2 else 0)) % 16 == 15:
				c = dark
			img.set_pixel(x, y, c)
	return _tex(img)


## Green felt with a faint gold circle in the middle (where the dice land).
static func felt(green: Color, dark: Color, gold: Color) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var c := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			var col := green if rng.randf() > 0.25 else dark
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if absf(r - 13.0) < 0.7 or absf(r - 10.0) < 0.5:
				col = green.lerp(gold, 0.55)
			img.set_pixel(x, y, col)
	return _tex(img)


static func banner(cloth: Color, gold: Color) -> ImageTexture:
	var img := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	img.fill(cloth)
	for y in 22:
		img.set_pixel(0, y, gold)
		img.set_pixel(11, y, gold)
	for x in 12:
		img.set_pixel(x, 0, gold)
	# a star emblem and a pointed bottom
	for p: Vector2i in [Vector2i(6, 7), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 9),
			Vector2i(4, 8), Vector2i(8, 8), Vector2i(6, 6), Vector2i(6, 10)]:
		img.set_pixel(p.x, p.y, gold)
	for y in range(17, 22):
		for x in 12:
			if absi(x * 2 - 11) < (y - 16) * 2:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return _tex(img)


## Soft ring of light with runes for under the dice (used additively).
static func ring() -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := maxf(0.0, 1.0 - absf(r - 18.0) / 2.5) + maxf(0.0, 1.0 - absf(r - 12.0) / 1.2) * 0.6
			var ang := atan2(y - c.y, x - c.x)
			if r > 13.5 and r < 16.5 and int((ang + PI) * 6.0) % 2 == 0:
				a = maxf(a, 0.45)  # rune marks between the rings
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return _tex(img)


## Head-and-shoulders portrait (16x16) for the top bar, in a Character3D look's colours.
static func portrait(look_name: String) -> ImageTexture:
	var look: Dictionary = Character3D.LOOKS[look_name]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color("1c140f"))
	var hair: Color = look["hair"]
	_rect(img, 1, 13, 14, 3, look["robe"])  # shoulders
	_rect(img, 2, 2, 12, 11, look["hair_dark"])  # hair behind
	_rect(img, 4, 4, 8, 8, look["skin"])  # face
	_rect(img, 3, 2, 10, 2, hair)  # fringe
	_rect(img, 3, 4, 1, 6, hair)
	_rect(img, 12, 4, 1, 6, hair)
	var eye: Color = look["eye"]
	_rect(img, 5, 7, 2, 2, eye)
	_rect(img, 9, 7, 2, 2, eye)
	img.set_pixel(5, 7, Color.WHITE)
	img.set_pixel(9, 7, Color.WHITE)
	_rect(img, 7, 10, 2, 1, Color("b45a5a"))
	match look["extra"]:
		"spiky":
			for x: int in [3, 6, 9, 12]:
				_rect(img, x, 0, 1, 2, hair)
			_rect(img, 1, 13, 14, 1, look["trim"])  # scarf
		"helmet":
			var steel: Color = look["robe"]
			_rect(img, 2, 1, 12, 2, steel)
			_rect(img, 2, 3, 2, 9, steel)
			_rect(img, 12, 3, 2, 9, steel)
			_rect(img, 7, 0, 2, 1, look["trim"])  # plume
		"hood":
			_rect(img, 2, 1, 12, 2, look["robe"])
			_rect(img, 1, 3, 2, 9, look["robe"])
			_rect(img, 13, 3, 2, 9, look["robe"])
		"dragon":
			_rect(img, 2, 0, 1, 3, look["hair"])  # horns
			_rect(img, 13, 0, 1, 3, look["hair"])
			_rect(img, 6, 10, 4, 2, look["skin"].lightened(0.1))  # snout
	return ImageTexture.create_from_image(img)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


## A chibi face for the front of a character's head: big eyes, a small mouth, blush.
## mode: "open", "blink" (eyes shut), "hurt" (squeezed > < eyes, open mouth, sweat drop)
## or "ko" (x x eyes, flat mouth).
static func face(skin: Color, eye: Color, mode := "open") -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(skin)
	var dark := Color("1e1218")
	var mouth := Color("b45a5a")
	for ex: int in [3, 9]:
		match mode:
			"blink":
				_rect(img, ex, 9, 4, 1, dark)
			"hurt":
				# > on the left eye, < on the right
				var left := ex == 3
				for i in 3:
					img.set_pixel(ex + (i if left else 3 - i), 7 + i, dark)
					img.set_pixel(ex + (i if left else 3 - i), 11 - i, dark)
			"ko":
				for i in 4:
					img.set_pixel(ex + i, 7 + i, dark)
					img.set_pixel(ex + 3 - i, 7 + i, dark)
			_:
				for y in range(6, 11):
					for x in range(ex, ex + 4):
						var edge := y == 6 or x == ex or x == ex + 3
						img.set_pixel(x, y, dark if edge else (eye if y > 7 else eye.lightened(0.3)))
				img.set_pixel(ex + 1, 7, Color.WHITE)  # shine
	match mode:
		"hurt":
			_rect(img, 7, 12, 2, 3, Color("7a1e24"))  # "ouch" mouth
			_rect(img, 13, 3, 1, 2, Color("8fd3ff"))  # sweat drop
			img.set_pixel(13, 5, Color("8fd3ff"))
		"ko":
			_rect(img, 6, 13, 4, 1, mouth)
		_:
			for x in range(7, 9):
				img.set_pixel(x, 13, mouth)
	for p: Vector2i in [Vector2i(2, 11), Vector2i(3, 11), Vector2i(12, 11), Vector2i(13, 11)]:
		img.set_pixel(p.x, p.y, skin.lerp(Color("ff8080"), 0.35))
	return ImageTexture.create_from_image(img)


static var _slashes: Dictionary = {}


## Drop cached textures (called when the table closes, before the renderer shuts down).
static func clear() -> void:
	_slashes.clear()


## A white crescent slash (bright edge, fading tail), turned by `angle` radians; tinted by
## the material. Cached per angle.
static func slash(angle: float) -> ImageTexture:
	var key := snappedf(angle, 0.01)
	if _slashes.has(key):
		return _slashes[key]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			var p := (Vector2(x + 0.5, y + 0.5) - c).rotated(-angle)
			# a thin moon: inside the big circle, outside a shifted one
			var outer := p.length() / 14.0
			var inner := (p - Vector2(0, 5)).length() / 13.0
			var a := 0.0
			if outer < 1.0 and inner > 1.0:
				a = clampf((inner - 1.0) * 4.0, 0.0, 1.0) * clampf(1.0 - absf(p.x) / 14.0, 0.0, 1.0) * 1.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_slashes[key] = tex
	return tex


## Soft round glow, brightest in the middle (aura behind a cursed or buffed bot).
static func glow() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c) / (n / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) * 0.8))
	return _tex(img)


const PIPS := {
	1: [Vector2i(7, 7)],
	2: [Vector2i(4, 4), Vector2i(10, 10)],
	3: [Vector2i(4, 4), Vector2i(7, 7), Vector2i(10, 10)],
	4: [Vector2i(4, 4), Vector2i(10, 4), Vector2i(4, 10), Vector2i(10, 10)],
	5: [Vector2i(4, 4), Vector2i(10, 4), Vector2i(7, 7), Vector2i(4, 10), Vector2i(10, 10)],
	6: [Vector2i(4, 3), Vector2i(10, 3), Vector2i(4, 7), Vector2i(10, 7), Vector2i(4, 11), Vector2i(10, 11)],
}


static func die_face(value: int) -> ImageTexture:
	var img := Image.create(15, 15, false, Image.FORMAT_RGB8)
	img.fill(Color("f3ead6"))
	for i in 15:  # darker edge so the cube reads as a cube
		for p: Vector2i in [Vector2i(i, 0), Vector2i(i, 14), Vector2i(0, i), Vector2i(14, i)]:
			img.set_pixel(p.x, p.y, Color("b8a888"))
	var pip := Color("b0242c") if value == 1 else Color("2a1d12")
	for p: Vector2i in PIPS[value]:
		for dy in 2:
			for dx in 2:
				img.set_pixel(p.x + dx - (1 if value == 1 else 0), p.y + dy - (1 if value == 1 else 0), pip)
	if value == 1:  # big red pip
		for p: Vector2i in [Vector2i(6, 5), Vector2i(7, 5), Vector2i(5, 6), Vector2i(8, 6), Vector2i(5, 7),
				Vector2i(8, 7), Vector2i(6, 8), Vector2i(7, 8)]:
			img.set_pixel(p.x, p.y, pip)
	var tex := ImageTexture.create_from_image(img)
	return tex
