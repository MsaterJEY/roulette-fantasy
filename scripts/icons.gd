class_name Icons
extends RefCounted
## Pixel icons for cards and effects: res://assets/icons/<id>.png (made by tools/make_icons.py;
## replace the files with real art). Effect ids that share a card's id use that card's icon.

static var _cache: Dictionary = {}


static func get_icon(id: String) -> Texture2D:
	if not _cache.has(id):
		var path := "res://assets/icons/%s.png" % id
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]


## A TextureRect showing the icon crisp (nearest) at `px` x `px`.
static func rect(id: String, px: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = get_icon(id)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(px, px)
	t.size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Drop the cached textures. Called when the table closes: a static cache would otherwise
## outlive the renderer at exit and be reported as leaked.
static func clear() -> void:
	_cache.clear()
