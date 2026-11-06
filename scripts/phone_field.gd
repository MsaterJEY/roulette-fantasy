class_name PhoneField
extends Node
## On a phone's browser: a real text box of the page, laid over `edit`. Godot opens the keyboard
## from its frame loop, not from the tap itself, and some phones (iPhones above all) only open
## it for a tap on a real box; the browser also moves a real box clear of the keyboard. `edit`
## keeps the text, so the game reads it as usual; Enter submits it. Add it as a child of
## anything once `wanted()`.

var edit: LineEdit
var _text := ""
var _box := Rect2()
var _shown := false


static func wanted() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("'ontouchstart' in window", true))


func _init(p_edit: LineEdit) -> void:
	edit = p_edit


func _ready() -> void:
	edit.focus_mode = Control.FOCUS_NONE  # the page's box takes the taps, and no Godot keyboard
	edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	JavaScriptBridge.eval("""(function(){
		var e=document.createElement('input');
		e.type='text';e.autocomplete='off';e.placeholder=%s;e.setAttribute('enterkeyhint','send');
		e.style.cssText='position:fixed;display:none;z-index:10;box-sizing:border-box;margin:0;padding:0 8px;'
			+'font-size:16px;color:#3b2412;background:#f6ead0;border:2px solid #a97c2f;border-radius:6px;outline:none';
		e.addEventListener('keydown',function(v){if(v.key==='Enter'){v.preventDefault();window.rfFieldEnter=true}});
		document.body.appendChild(e);window.rfField=e;
	})()""" % JSON.stringify(edit.placeholder_text), true)


func _exit_tree() -> void:
	JavaScriptBridge.eval("if(window.rfField){window.rfField.remove();window.rfField=null}", true)


func _process(_delta: float) -> void:
	var show := edit.is_visible_in_tree()
	if show != _shown:
		_shown = show
		_box = Rect2()
		# the focus opens the keyboard where the phone allows it without a tap
		JavaScriptBridge.eval("rfField.style.display='%s';rfField.%s()" % [
			"block" if show else "none", "focus" if show else "blur"], true)
	if not show:
		return
	var t := edit.get_viewport().get_final_transform() * edit.get_global_transform_with_canvas()
	var box := Rect2(t.origin, edit.size * t.get_scale())
	if box != _box:  # canvas pixels to page pixels
		_box = box
		JavaScriptBridge.eval("""(function(){var c=document.getElementById('canvas'),r=c.getBoundingClientRect(),k=r.width/c.width,s=rfField.style;
			s.left=(r.left+%f*k)+'px';s.top=(r.top+%f*k)+'px';s.width=(%f*k)+'px';s.height=(%f*k)+'px'})()""" % [
			box.position.x, box.position.y, box.size.x, box.size.y], true)
	if edit.text != _text:  # the game cleared it
		_text = edit.text
		JavaScriptBridge.eval("rfField.value=%s" % JSON.stringify(_text), true)
	var typed := str(JavaScriptBridge.eval("rfField.value", true))
	if typed != _text:
		_text = typed
		edit.text = typed
	if bool(JavaScriptBridge.eval("(function(){var v=!!window.rfFieldEnter;window.rfFieldEnter=false;return v})()", true)):
		edit.text_submitted.emit(_text)
