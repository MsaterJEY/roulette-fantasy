class_name Vignette
extends ColorRect
## A coloured glow round the screen edges, used for effects on you: red flash when hit,
## blue when you block, a dark purple haze while blind, soft blue while under truce.

const SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float strength = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.75);
	float v = smoothstep(0.18, 0.62, length(d));
	COLOR = vec4(tint.rgb, v * strength);
}
"""

var strength := 0.0:
	set(v):
		strength = v
		(material as ShaderMaterial).set_shader_parameter("strength", v)


func _init(tint: Color) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	set_tint(tint)
	strength = 0.0


func set_tint(tint: Color) -> void:
	(material as ShaderMaterial).set_shader_parameter("tint", tint)


## Flash up to `peak` and fade back to `rest`.
func flash(tint: Color, peak: float, rest: float = 0.0) -> void:
	set_tint(tint)
	var t := create_tween()
	t.tween_property(self, "strength", peak, 0.08)
	t.tween_property(self, "strength", rest, 0.6)
