extends CanvasLayer

const MAP_SIZE := 210.0
const MAP_MARGIN := 26.0
const MAP_RANGE := 150.0

var _font: SystemFont
var _root: Control
var _vignette: ColorRect
var _flash: ColorRect
var _fade: ColorRect
var _damage: ColorRect

var _brand: Control
var _brand_kicker: Label
var _brand_title: Label
var _brand_bar: ColorRect
var _brand_sub: Label

var _objective: Control
var _obj_text: Label
var _obj_sub: Label

var _score_box: Control
var _score_label: Label
var _deliver_label: Label

var _speed_box: Control
var _speed_value: Label
var _speed_caption: Label
var _speed_bar: ColorRect
var _speed_bar_bg: ColorRect

var _health_box: Control
var _health_caption: Label
var _pips: Array[ColorRect] = []

var _map: Control
var _road_xs := PackedFloat32Array()
var _road_zs := PackedFloat32Array()
var _half := 441.0
var _car_pos := Vector2.ZERO
var _heading := 0.0
var _waypoint := Vector2.ZERO
var _traffic := PackedVector2Array()
var _has_waypoint := false

var _prompt: Control
var _prompt_main: Label
var _prompt_sub: Label

var _over: Control
var _over_dim: ColorRect
var _over_title: Label
var _over_sub: Label
var _over_best: Label
var _over_prompt: Label

var _message: Label
var _message_time := 0.0

var _mode := "menu"
var _t := 0.0
var _flash_amt := 0.0
var _damage_amt := 0.0
var _over_fade := 1.0
var _last_health := 3
var _size := Vector2(1600, 900)


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
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){\n    vec2 uv = SCREEN_UV - vec2(0.5);\n    float d = length(uv * vec2(1.0, 1.25));\n    float v = smoothstep(0.35, 1.0, d);\n    COLOR = vec4(0.03, 0.015, 0.008, v * 0.55);\n}\n"
	var vmat := ShaderMaterial.new()
	vmat.shader = sh
	_vignette.material = vmat
	_root.add_child(_vignette)

	_damage = ColorRect.new()
	_damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage.color = Color(0.7, 0.05, 0.02, 0.0)
	_root.add_child(_damage)

	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.clip_contents = true
	_root.add_child(_map)
	_map.draw.connect(_draw_map)

	_build_brand()
	_build_objective()
	_build_score()
	_build_speed()
	_build_health()
	_build_prompt()
	_build_message()
	_build_over()

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.35, 0.05, 0.0)
	_root.add_child(_flash)

	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.02, 0.01, 0.008, 1.0)
	_root.add_child(_fade)

	_size = get_viewport().get_visible_rect().size
	_layout()
	get_viewport().size_changed.connect(_layout)
	set_mode("menu")


func _mk(text: String, size: int, color: Color, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.spacing_glyph = spacing
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _build_brand() -> void:
	_brand = Control.new()
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_brand)
	_brand_kicker = _mk("LOS ANGELES   ·   10:14 AM", 14, Color(0.95, 0.79, 0.64, 0.9), 4)
	_brand_kicker.position = Vector2(3, 0)
	_brand.add_child(_brand_kicker)
	_brand_title = _mk("2012", 86, Color(0.98, 0.955, 0.92, 1.0), -2)
	_brand_title.position = Vector2(0, 12)
	_brand.add_child(_brand_title)
	_brand_bar = ColorRect.new()
	_brand_bar.color = Color(0.94, 0.42, 0.15, 1.0)
	_brand_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand_bar.position = Vector2(5, 112)
	_brand_bar.size = Vector2(190, 2)
	_brand.add_child(_brand_bar)
	_brand_sub = _mk("THE CITY IS COMING APART", 15, Color(0.96, 0.6, 0.3, 1.0), 5)
	_brand_sub.position = Vector2(4, 120)
	_brand.add_child(_brand_sub)


func _build_objective() -> void:
	_objective = Control.new()
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_objective)
	_obj_text = _mk("DROP-OFF  0 M", 24, Color(1.0, 0.95, 0.88, 1.0), 4)
	_obj_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_text.size = Vector2(560, 34)
	_objective.add_child(_obj_text)
	_obj_sub = _mk("FOLLOW THE ORANGE MARKER", 12, Color(0.94, 0.72, 0.45, 0.85), 4)
	_obj_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_sub.position = Vector2(0, 34)
	_obj_sub.size = Vector2(560, 20)
	_objective.add_child(_obj_sub)


func _build_score() -> void:
	_score_box = Control.new()
	_score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_score_box)
	_score_label = _mk("0", 40, Color(0.99, 0.96, 0.9, 1.0), 0)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.size = Vector2(240, 48)
	_score_box.add_child(_score_label)
	_deliver_label = _mk("SCORE   ·   DROP-OFFS 0", 12, Color(0.93, 0.63, 0.4, 0.9), 3)
	_deliver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_deliver_label.position = Vector2(0, 44)
	_deliver_label.size = Vector2(240, 20)
	_score_box.add_child(_deliver_label)


func _build_speed() -> void:
	_speed_box = Control.new()
	_speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_speed_box)
	_speed_value = _mk("0", 52, Color(0.99, 0.96, 0.9, 1.0), -1)
	_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_value.size = Vector2(200, 60)
	_speed_box.add_child(_speed_value)
	_speed_caption = _mk("KM/H", 12, Color(0.93, 0.63, 0.4, 0.9), 5)
	_speed_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_caption.position = Vector2(0, 56)
	_speed_caption.size = Vector2(200, 20)
	_speed_box.add_child(_speed_caption)
	_speed_bar_bg = ColorRect.new()
	_speed_bar_bg.color = Color(0.1, 0.08, 0.07, 0.6)
	_speed_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_bar_bg.position = Vector2(0, 80)
	_speed_bar_bg.size = Vector2(200, 5)
	_speed_box.add_child(_speed_bar_bg)
	_speed_bar = ColorRect.new()
	_speed_bar.color = Color(0.95, 0.5, 0.16, 0.95)
	_speed_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_bar.position = Vector2(0, 80)
	_speed_bar.size = Vector2(0, 5)
	_speed_box.add_child(_speed_bar)


func _build_health() -> void:
	_health_box = Control.new()
	_health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_health_box)
	for i in 3:
		var p := ColorRect.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.color = Color(0.95, 0.45, 0.16, 0.95)
		p.position = Vector2(i * 36, 0)
		p.size = Vector2(28, 6)
		_health_box.add_child(p)
		_pips.append(p)
	_health_caption = _mk("CHASSIS", 11, Color(0.9, 0.82, 0.72, 0.65), 4)
	_health_caption.position = Vector2(0, 13)
	_health_caption.size = Vector2(200, 18)
	_health_box.add_child(_health_caption)


func _build_prompt() -> void:
	_prompt = Control.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt)
	_prompt_main = _mk("PRESS SPACE TO DRIVE", 22, Color(0.99, 0.94, 0.86, 1.0), 6)
	_prompt_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_main.size = Vector2(680, 34)
	_prompt.add_child(_prompt_main)
	_prompt_sub = _mk("W / S  DRIVE          A / D  STEER          SPACE  HANDBRAKE          R  RESTART", 12, Color(0.92, 0.85, 0.76, 0.75), 3)
	_prompt_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_sub.position = Vector2(0, 36)
	_prompt_sub.size = Vector2(680, 22)
	_prompt.add_child(_prompt_sub)


func _build_message() -> void:
	_message = _mk("", 20, Color(1.0, 0.9, 0.75, 1.0), 4)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.size = Vector2(900, 30)
	_message.modulate.a = 0.0
	_root.add_child(_message)


func _build_over() -> void:
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_over)

	_over_dim = ColorRect.new()
	_over_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over_dim.color = Color(0.03, 0.015, 0.01, 0.62)
	_over.add_child(_over_dim)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_over.add_child(box)

	_over_title = _mk("THE CITY TOOK YOU", 42, Color(1.0, 0.97, 0.92, 1.0), 3)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_title.custom_minimum_size = Vector2(0, 60)
	box.add_child(_over_title)

	_over_sub = _mk("SCORE  0", 18, Color(0.94, 0.72, 0.48, 0.95), 4)
	_over_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_sub)

	_over_best = _mk("BEST  0", 13, Color(0.9, 0.85, 0.78, 0.7), 3)
	_over_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_best)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, 22)
	box.add_child(spacer)

	_over_prompt = _mk("PRESS SPACE TO DRIVE AGAIN", 16, Color(0.98, 0.92, 0.84, 0.95), 5)
	_over_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_prompt)


func _layout() -> void:
	_size = get_viewport().get_visible_rect().size
	_brand.position = Vector2(46, 32)
	_objective.position = Vector2(_size.x * 0.5 - 280, 34)
	_score_box.position = Vector2(_size.x - 46 - 240, 32)
	_speed_box.position = Vector2(_size.x - 46 - 200, _size.y - 110)
	_health_box.position = Vector2(46, _size.y - 60)
	_prompt.position = Vector2(_size.x * 0.5 - 340, _size.y - 140)
	_message.position = Vector2(_size.x * 0.5 - 450, _size.y - 190)
	_map.position = Vector2(MAP_MARGIN, _size.y - MAP_SIZE - MAP_MARGIN)
	_map.size = Vector2(MAP_SIZE, MAP_SIZE)


func setup_map(road_xs: PackedFloat32Array, road_zs: PackedFloat32Array, half: float) -> void:
	_road_xs = road_xs
	_road_zs = road_zs
	_half = half


func set_mode(m: String) -> void:
	_mode = m
	var play: bool = m == "play" or m == "dying" or m == "over"
	_objective.visible = play
	_score_box.visible = play
	_speed_box.visible = play
	_health_box.visible = play
	_map.visible = play
	_prompt.visible = m == "menu"
	_brand.visible = m != "over"
	_brand.modulate.a = 0.55 if play else 1.0
	_over.visible = m == "over"
	if m == "play":
		_last_health = -1


func update_hud(speed_kmh: float, health: int, score: int, deliveries: int, dist: float, _angle: float) -> void:
	_speed_value.text = str(int(round(speed_kmh)))
	var ratio := clampf(speed_kmh / 150.0, 0.0, 1.0)
	_speed_bar.size = Vector2(200.0 * ratio, 5)
	_score_label.text = _fmt(score)
	_deliver_label.text = "SCORE   ·   DROP-OFFS %d" % deliveries
	if health != _last_health:
		_last_health = health
		for i in _pips.size():
			_pips[i].color = Color(0.95, 0.45, 0.16, 0.95) if i < health else Color(0.32, 0.2, 0.14, 0.55)
	_obj_text.text = "DROP-OFF  %s M" % _fmt(int(dist))


func update_map(car_pos: Vector2, heading: float, waypoint: Vector2, has_wp: bool, traffic: PackedVector2Array) -> void:
	_car_pos = car_pos
	_heading = heading
	_waypoint = waypoint
	_has_waypoint = has_wp
	_traffic = traffic
	if _map.visible:
		_map.queue_redraw()


func _draw_map() -> void:
	var size := _map.size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.035, 0.035, 0.82))
	var scale := (size.x * 0.5) / MAP_RANGE
	var center := size * 0.5
	draw_set_transform(center, _heading, Vector2(scale, scale))
	var road_col := Color(0.62, 0.6, 0.58, 0.9)
	for x in _road_xs:
		draw_line(Vector2(x, -_half) - _car_pos, Vector2(x, _half) - _car_pos, road_col, 9.0)
	for z in _road_zs:
		draw_line(Vector2(-_half, z) - _car_pos, Vector2(_half, z) - _car_pos, road_col, 9.0)
	draw_set_transform(center, _heading, Vector2(scale, scale))
	for t in _traffic:
		draw_circle(t - _car_pos, 4.0, Color(0.95, 0.95, 0.9, 0.85))
	if _has_waypoint:
		var wp := _waypoint - _car_pos
		var r := 9.0
		draw_colored_polygon(PackedVector2Array([wp + Vector2(0, -r), wp + Vector2(r, 0), wp + Vector2(0, r), wp + Vector2(-r, 0)]), Color(1.0, 0.55, 0.1, 1.0))
	draw_set_transform(center, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)]), Color(1.0, 1.0, 1.0, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.55, 0.2, 0.35), false, 2.0)


func flash(amount: float) -> void:
	_flash_amt = maxf(_flash_amt, amount)


func damage_flash(amount: float) -> void:
	_damage_amt = maxf(_damage_amt, amount)


func show_message(text: String, seconds: float = 2.4) -> void:
	_message.text = text
	_message_time = seconds


func show_over(cause: String, score: int, deliveries: int, best: int) -> void:
	set_mode("over")
	if cause == "wreck":
		_over_title.text = "THE LIMO IS WRECKED"
	else:
		_over_title.text = "THE GROUND GAVE WAY"
	_over_sub.text = "SCORE  %s      ·      DROP-OFFS  %d" % [_fmt(score), deliveries]
	_over_best.text = "BEST  %s" % _fmt(best)
	_over_fade = 0.0
	_over.modulate.a = 0.0


func fade_in() -> void:
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.7)


func intro_fade() -> void:
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.6).set_delay(0.1)


func _process(delta: float) -> void:
	_t += delta
	var blink := 0.78 + 0.22 * sin(_t * 3.4)
	if _mode == "menu":
		_prompt_main.modulate.a = blink
	if _mode == "over":
		_over_prompt.modulate.a = blink
		_over_fade = minf(1.0, _over_fade + delta * 3.2)
		_over.modulate.a = _over_fade
	_flash_amt = maxf(0.0, _flash_amt - delta * 1.9)
	_flash.color.a = _flash_amt
	_damage_amt = maxf(0.0, _damage_amt - delta * 1.4)
	_damage.color.a = _damage_amt
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time, 0.0, 1.0)


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
