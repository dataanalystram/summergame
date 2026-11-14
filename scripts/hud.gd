extends CanvasLayer

var _font: SystemFont
var _root: Control
var _vignette: ColorRect
var _flash: ColorRect
var _fade: ColorRect

var _brand: Control
var _brand_kicker: Label
var _brand_title: Label
var _brand_bar: ColorRect
var _brand_sub: Label

var _prompt: Control
var _prompt_main: Label
var _prompt_sub: Label

var _stats: Control
var _dist_value: Label
var _dist_caption: Label
var _best_label: Label

var _speed_box: Control
var _speed_value: Label
var _speed_caption: Label

var _health_box: Control
var _health_caption: Label
var _pips: Array[ColorRect] = []

var _hint: Label

var _over: Control
var _over_dim: ColorRect
var _over_title: Label
var _over_sub: Label
var _over_best: Label
var _over_prompt: Label

var _mode := "menu"
var _flash_amt := 0.0
var _over_fade := 1.0
var _t := 0.0
var _last_health := 3
var _hint_alpha := 1.0
var _play_time := 0.0
var _size := Vector2(1152, 648)


func _ready() -> void:
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Helvetica Neue", "SF Pro Display", "Helvetica", "Arial"])
	_font.font_weight = 700

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(1, 1, 1, 1)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){\n    vec2 uv = SCREEN_UV - vec2(0.5);\n    float d = length(uv * vec2(1.0, 1.3));\n    float v = smoothstep(0.32, 0.95, d);\n    COLOR = vec4(0.03, 0.015, 0.008, v * 0.55);\n}\n"
	var vmat := ShaderMaterial.new()
	vmat.shader = sh
	_vignette.material = vmat
	_root.add_child(_vignette)

	_build_brand()
	_build_prompt()
	_build_stats()
	_build_speed()
	_build_health()
	_build_hint()
	_build_over()

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.85, 0.16, 0.06, 0.0)
	_root.add_child(_flash)

	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.02, 0.01, 0.008, 1.0)
	_root.add_child(_fade)

	_size = get_viewport().get_visible_rect().size
	_layout()
	get_viewport().size_changed.connect(_on_resize)
	set_mode("menu")


func _mk_label(text: String, size: int, color: Color, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.spacing_glyph = spacing
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _build_brand() -> void:
	_brand = Control.new()
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_brand)

	_brand_kicker = _mk_label("LOS ANGELES   ·   10:14 AM", 14, Color(0.95, 0.79, 0.64, 0.9), 4)
	_brand_kicker.position = Vector2(3, 0)
	_brand.add_child(_brand_kicker)

	_brand_title = _mk_label("2012", 96, Color(0.98, 0.955, 0.92, 1.0), -2)
	_brand_title.position = Vector2(0, 14)
	_brand.add_child(_brand_title)

	_brand_bar = ColorRect.new()
	_brand_bar.color = Color(0.94, 0.42, 0.15, 1.0)
	_brand_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand_bar.position = Vector2(5, 125)
	_brand_bar.size = Vector2(210, 2)
	_brand.add_child(_brand_bar)

	_brand_sub = _mk_label("THE ESCAPE", 21, Color(0.96, 0.6, 0.3, 1.0), 9)
	_brand_sub.position = Vector2(4, 134)
	_brand.add_child(_brand_sub)


func _build_prompt() -> void:
	_prompt = Control.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt)
	_prompt_main = _mk_label("PRESS SPACE TO DRIVE", 22, Color(0.99, 0.94, 0.86, 1.0), 6)
	_prompt_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_main.size = Vector2(620, 34)
	_prompt.add_child(_prompt_main)
	_prompt_sub = _mk_label("A / D  STEER          S  BRAKE", 13, Color(0.92, 0.85, 0.76, 0.75), 3)
	_prompt_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_sub.position = Vector2(0, 36)
	_prompt_sub.size = Vector2(620, 22)
	_prompt.add_child(_prompt_sub)


func _build_stats() -> void:
	_stats = Control.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stats)
	_dist_value = _mk_label("0", 44, Color(0.99, 0.96, 0.9, 1.0), 0)
	_dist_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dist_value.size = Vector2(240, 52)
	_stats.add_child(_dist_value)
	_dist_caption = _mk_label("METRES", 12, Color(0.93, 0.63, 0.4, 0.9), 5)
	_dist_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dist_caption.position = Vector2(0, 50)
	_dist_caption.size = Vector2(240, 20)
	_stats.add_child(_dist_caption)
	_best_label = _mk_label("BEST  0", 13, Color(0.9, 0.84, 0.76, 0.7), 3)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best_label.position = Vector2(0, 76)
	_best_label.size = Vector2(240, 20)
	_stats.add_child(_best_label)


func _build_speed() -> void:
	_speed_box = Control.new()
	_speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_speed_box)
	_speed_value = _mk_label("0", 46, Color(0.99, 0.96, 0.9, 1.0), -1)
	_speed_value.size = Vector2(160, 54)
	_speed_box.add_child(_speed_value)
	_speed_caption = _mk_label("KM/H", 12, Color(0.93, 0.63, 0.4, 0.9), 5)
	_speed_caption.position = Vector2(3, 52)
	_speed_caption.size = Vector2(160, 20)
	_speed_box.add_child(_speed_caption)


func _build_health() -> void:
	_health_box = Control.new()
	_health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_health_box)
	for i in 3:
		var p := ColorRect.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.color = Color(0.95, 0.45, 0.16, 0.95)
		p.position = Vector2(i * 34, 0)
		p.size = Vector2(26, 5)
		_health_box.add_child(p)
		_pips.append(p)
	_health_caption = _mk_label("CHASSIS", 11, Color(0.9, 0.82, 0.72, 0.6), 4)
	_health_caption.position = Vector2(0, 12)
	_health_caption.size = Vector2(200, 18)
	_health_box.add_child(_health_caption)


func _build_hint() -> void:
	_hint = _mk_label("A / D  STEER          S  BRAKE", 12, Color(0.94, 0.88, 0.8, 0.65), 3)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.size = Vector2(360, 20)
	_root.add_child(_hint)


func _build_over() -> void:
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_over)

	_over_dim = ColorRect.new()
	_over_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over_dim.color = Color(0.03, 0.015, 0.01, 0.55)
	_over.add_child(_over_dim)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_over.add_child(box)

	_over_title = _mk_label("THE GROUND GAVE WAY", 42, Color(1.0, 0.97, 0.92, 1.0), 3)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_title.custom_minimum_size = Vector2(0, 60)
	box.add_child(_over_title)

	_over_sub = _mk_label("YOU SURVIVED  0 M", 17, Color(0.94, 0.72, 0.48, 0.95), 4)
	_over_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_sub)

	_over_best = _mk_label("BEST  0 M", 13, Color(0.9, 0.85, 0.78, 0.7), 3)
	_over_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_best)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer)

	_over_prompt = _mk_label("PRESS SPACE TO DRIVE AGAIN", 16, Color(0.98, 0.92, 0.84, 0.95), 5)
	_over_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_prompt)


func _layout() -> void:
	_size = get_viewport().get_visible_rect().size
	_brand.position = Vector2(54, 34)
	_prompt.position = Vector2(_size.x * 0.5 - 310, _size.y - 146)
	_stats.position = Vector2(_size.x - 56 - 240, 38)
	_speed_box.position = Vector2(54, _size.y - 108)
	_health_box.position = Vector2(_size.x * 0.5 - 50, _size.y - 54)
	_hint.position = Vector2(_size.x - 56 - 360, _size.y - 42)


func _on_resize() -> void:
	_layout()


func _process(delta: float) -> void:
	_t += delta
	if _mode == "play":
		_play_time += delta
	var blink := 0.78 + 0.22 * sin(_t * 3.4)
	if _mode == "menu":
		_prompt_main.modulate.a = blink
	if _mode == "over":
		_over_prompt.modulate.a = blink
		_over_fade = minf(1.0, _over_fade + delta * 3.2)
		_over.modulate.a = _over_fade
	_flash_amt = maxf(0.0, _flash_amt - delta * 1.9)
	_flash.color.a = _flash_amt
	if _mode == "play" and _play_time > 9.0:
		_hint_alpha = maxf(0.0, _hint_alpha - delta * 0.9)
		_hint.modulate.a = _hint_alpha


func set_mode(m: String) -> void:
	_mode = m
	var play: bool = m == "play" or m == "dying" or m == "over"
	_stats.visible = play
	_speed_box.visible = play
	_health_box.visible = play
	_prompt.visible = m == "menu"
	_over.visible = m == "over"
	_brand.modulate.a = 0.55 if play else 1.0
	if m == "over":
		_stats.visible = false
		_speed_box.visible = false
		_health_box.visible = false
		_brand.visible = false
	else:
		_brand.visible = true
	if m == "menu":
		_play_time = 0.0
		_hint_alpha = 1.0
		_hint.modulate.a = 1.0
		_hint.visible = false
	elif m == "play":
		_play_time = 0.0
		_hint_alpha = 1.0
		_hint.modulate.a = 1.0
		_hint.visible = true
		_last_health = -1
	elif m == "dying":
		_hint.visible = false
	elif m == "over":
		_hint.visible = false


func update_stats(distance_m: int, kmh: float, best_m: int, health: int) -> void:
	_dist_value.text = _fmt(distance_m)
	_best_label.text = "BEST  %s" % _fmt(best_m)
	_speed_value.text = str(int(round(kmh)))
	if health != _last_health:
		_last_health = health
		for i in _pips.size():
			if i < health:
				_pips[i].color = Color(0.95, 0.45, 0.16, 0.95)
			else:
				_pips[i].color = Color(0.32, 0.2, 0.14, 0.55)


func set_best(best_m: int) -> void:
	_best_label.text = "BEST  %s" % _fmt(best_m)


func show_over(cause: String, distance_m: int, best_m: int) -> void:
	set_mode("over")
	if cause == "debris":
		_over_title.text = "THE LIMO IS WRECKED"
	else:
		_over_title.text = "THE GROUND GAVE WAY"
	_over_sub.text = "YOU SURVIVED  %s M" % _fmt(distance_m)
	_over_best.text = "BEST  %s M" % _fmt(best_m)
	_over_fade = 0.0
	_over.modulate.a = 0.0


func flash(amount: float) -> void:
	_flash_amt = maxf(_flash_amt, amount)


func fade_in() -> void:
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.85)


func intro_fade() -> void:
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.8).set_delay(0.15)


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out
