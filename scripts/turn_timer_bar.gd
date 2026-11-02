class_name TurnTimerBar
extends Control
## Time left as a line running round a seat's frame: starts at the top centre, goes clockwise,
## and shrinks back towards the start as `fraction` falls from 1 to 0. Red when time is short.

const WIDTH := 5.0
const RADIUS := 9.0

var fraction := 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if absf(v - fraction) > 0.0005:
			fraction = v
			queue_redraw()
var warning := false:
	set(v):
		if v != warning:
			warning = v
			queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var inset := WIDTH / 2
	var path := _rounded_path(Rect2(Vector2(inset, inset), size - Vector2(WIDTH, WIDTH)), RADIUS)
	draw_polyline(path, Color(0.08, 0.05, 0.03, 0.85), WIDTH, true)  # the empty track
	var part := _cut(path, fraction)
	if part.size() >= 2:
		draw_polyline(part, Color("ff5a4f") if warning else UiStyle.ACTIVE.lightened(0.25), WIDTH, true)


## Rounded rectangle outline, clockwise from the top centre back to it.
static func _rounded_path(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(r.position.x + r.size.x / 2, r.position.y)])
	var corners := [
		[Vector2(r.end.x - radius, r.position.y + radius), -PI / 2],
		[Vector2(r.end.x - radius, r.end.y - radius), 0.0],
		[Vector2(r.position.x + radius, r.end.y - radius), PI / 2],
		[Vector2(r.position.x + radius, r.position.y + radius), PI],
	]
	for corner: Array in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for k in 7:
			var a := start + (PI / 2) * k / 6.0
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
	pts.append(pts[0])
	return pts


## The first `frac` of the path's length.
static func _cut(path: PackedVector2Array, frac: float) -> PackedVector2Array:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var left := total * frac
	var out := PackedVector2Array([path[0]])
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if seg >= left:
			out.append(path[i - 1].lerp(path[i], left / seg if seg > 0 else 0.0))
			return out
		left -= seg
		out.append(path[i])
	return out
