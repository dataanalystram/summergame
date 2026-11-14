extends Node3D
# Open-world district for "2012: The Escape". Fixed map, free driving, beacon missions, sinkholes.

const GRID := 10            # blocks per side
const PITCH := 100.0        # block centre spacing
const ROAD_W := 16.0
const SINK_TRIGGER := 70.0
const LIMO_PATH := "res://art/limo/3d_ee280d55825b4afbb415e5a7_1787593437008.glb"
const SKY_SHADER := "res://shaders/apocalypse_sky.gdshader"
const BUILDINGS_DIR := "res://assets/packs/buildings/FBX/"
const CARS_DIR := "res://assets/packs/cars/FBX/"
const STREET_DIR := "res://assets/packs/street/FBX/"
const SAVE_PATH := "user://open_world.cfg"

var car: CityCar
var cam: Camera3D
var sinkholes: Array[Dictionary] = []   # {pos, radius, t, node}
var beacons: Array[Vector3] = []
var beacon_node: MeshInstance3D
var beacon_i := 0
var label: Label
var msg: Label
var t_run := 0.0
var best := 0.0
var rng := RandomNumberGenerator.new()
var half := 0.0

func _ready() -> void:
	rng.seed = 2012
	half = GRID * PITCH * 0.5
	_environment()
	_ground()
	_roads()
	_city()
	_traffic_props()
	_build_car()
	_build_beacons()
	_build_hud()
	_build_sinkholes()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = cfg.get_value("run", "best", 0.0)
	_respawn()

func ground_height_at(x: float, z: float) -> float:
	for s in sinkholes:
		if s.t > 0.0 and Vector2(x, z).distance_to(Vector2(s.pos.x, s.pos.z)) < s.radius * minf(s.t * 1.5, 1.0):
			return -12.0
	return 0.0

# ---------- world ----------
func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load(SKY_SHADER)
	sky_mat.set_shader_parameter("zenith_color", Color(0.055, 0.032, 0.04))
	sky_mat.set_shader_parameter("horizon_color", Color(0.95, 0.42, 0.16))
	sky_mat.set_shader_parameter("ground_color", Color(0.07, 0.04, 0.035))
	sky_mat.set_shader_parameter("sun_color", Color(1, 0.72, 0.38))
	sky_mat.set_shader_parameter("cloud_amount", 0.62)
	sky_mat.set_shader_parameter("cloud_scale", 2.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.5, 0.44)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.34, 0.2)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.65, 0.35)
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-24, 70, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)

func _static_box(pos: Vector3, size: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _ground() -> void:
	# one big slab of dark rubble ground; roads are drawn on top
	_static_box(Vector3(0, -0.5, 0), Vector3(half * 2 + 400, 1.0, half * 2 + 400), _mat(Color(0.16, 0.12, 0.1)), false)

func _roads() -> void:
	var asphalt := _mat(Color(0.07, 0.07, 0.075), 0.85)
	var paint := _mat(Color(0.9, 0.85, 0.7), 0.7)
	var span := GRID * PITCH + ROAD_W
	for i in GRID + 1:
		var p := -half + i * PITCH
		_static_box(Vector3(p, 0.02, 0), Vector3(ROAD_W, 0.06, span), asphalt, false)
		_static_box(Vector3(0, 0.025, p), Vector3(span, 0.06, ROAD_W), asphalt, false)
		# dashed centre lines
		var n := int(span / 12.0)
		for k in n:
			var o := -span * 0.5 + k * 12.0 + 3.0
			_static_box(Vector3(p, 0.07, o), Vector3(0.3, 0.02, 5.0), paint, false)
			_static_box(Vector3(o, 0.075, p), Vector3(5.0, 0.02, 0.3), paint, false)

func _load_scene(path: String) -> PackedScene:
	return load(path) as PackedScene

func _list(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".fbx"):
			out.append(dir + f)
	return out

func _limit_range(n: Node, dist: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = dist
	for c in n.get_children():
		_limit_range(c, dist)

func _place_fit(packed: PackedScene, pos: Vector3, footprint: float, yaw: float, add_collider := true) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var model := packed.instantiate()
	holder.add_child(model)
	var bb := CityCar.model_aabb(holder)
	var s := footprint / maxf(maxf(bb.size.x, bb.size.z), 0.01)
	holder.scale = Vector3(s, s, s)
	bb = CityCar.model_aabb(holder)
	holder.position = pos - Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	holder.rotation.y = yaw
	if add_collider:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bb.size
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)
		sb.global_position = pos + Vector3(0, bb.size.y * 0.5, 0)
	_limit_range(holder, 380.0)
	return holder

func _city() -> void:
	var files := _list(BUILDINGS_DIR)
	if files.is_empty():
		push_warning("no building models found")
		return
	var packs: Array[PackedScene] = []
	for f in files:
		var ps := _load_scene(f)
		if ps:
			packs.append(ps)
	for gx in GRID:
		for gz in GRID:
			var cx := -half + (gx + 0.5) * PITCH
			var cz := -half + (gz + 0.5) * PITCH
			var inner := PITCH - ROAD_W - 6.0
			for k in 4:
				var ox := (-1 if k % 2 == 0 else 1) * inner * 0.25
				var oz := (-1 if k < 2 else 1) * inner * 0.25
				var ps: PackedScene = packs[rng.randi() % packs.size()]
				_place_fit(ps, Vector3(cx + ox, 0, cz + oz), rng.randf_range(16.0, 24.0), rng.randi_range(0, 3) * PI * 0.5)

func _traffic_props() -> void:
	var cars := _list(CARS_DIR)
	var lights: Array[String] = []
	for f in _list(STREET_DIR):
		if f.contains("Streetlight_Single"):
			lights.append(f)
	var car_packs: Array[PackedScene] = []
	for f in cars:
		var ps := _load_scene(f)
		if ps:
			car_packs.append(ps)
	if not car_packs.is_empty():
		for i in 70:
			var along := rng.randf_range(-half, half)
			var lane := rng.randi_range(0, GRID)
			var line := -half + lane * PITCH + rng.randf_range(-5.0, 5.0)
			var on_x := rng.randf() < 0.5
			var pos := Vector3(line, 0, along) if on_x else Vector3(along, 0, line)
			var yaw := rng.randf_range(-0.6, 0.6) + (0.0 if on_x else PI * 0.5)
			_place_fit(car_packs[rng.randi() % car_packs.size()], pos, 4.6, yaw)
	if not lights.is_empty():
		var lp := _load_scene(lights[0])
		for gx in GRID + 1:
			for gz in GRID:
				var x := -half + gx * PITCH + ROAD_W * 0.5 + 1.0
				var z := -half + (gz + 0.5) * PITCH
				_place_fit(lp, Vector3(x, 0, z), 1.5, 0.0, false)

# ---------- player ----------
func _build_car() -> void:
	car = CityCar.new()
	car.world = self
	car.name = "Car"
	add_child(car)
	var packed := load(LIMO_PATH) as PackedScene
	car.attach_model(packed, 6.2)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	car.wrecked.connect(func(): _msg("WRECKED - respawning", 2.0); await get_tree().create_timer(2.0).timeout; _respawn())

func _respawn() -> void:
	for s in sinkholes:
		s.t = 0.0
		s.node.visible = false
	car.reset_car(Vector3(0.0, 0.0, half - 10.0), 0.0)
	beacon_i = 0
	t_run = 0.0
	_update_beacon()
	_msg("Reach the beacons. The city is coming apart.", 4.0)

func _process(delta: float) -> void:
	if car == null:
		return
	t_run += delta
	# chase camera
	var back := -car.forward_vector()
	var target := car.global_position + back * 11.0 + Vector3(0, 5.2, 0)
	cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-5.0 * delta))
	cam.look_at(car.global_position + Vector3(0, 1.6, 0) + car.forward_vector() * 6.0)
	# sinkholes
	for s in sinkholes:
		var d := Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(s.pos.x, s.pos.z))
		if s.t <= 0.0 and d < SINK_TRIGGER:
			s.t = 0.001
			s.node.visible = true
			_msg("The road is giving way!", 1.5)
		elif s.t > 0.0:
			s.t += delta
			s.node.scale = Vector3.ONE * minf(s.t * 1.5, 1.0)
	# beacon
	if beacon_i < beacons.size():
		var bp := beacons[beacon_i]
		if Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(bp.x, bp.z)) < 12.0:
			beacon_i += 1
			if beacon_i >= beacons.size():
				_finish()
			else:
				_msg("Checkpoint %d / %d" % [beacon_i, beacons.size()], 2.0)
				_update_beacon()
	var to := Vector3.ZERO
	if beacon_i < beacons.size():
		to = beacons[beacon_i] - car.global_position
	label.text = "%d km/h   HP %d   Beacon %d/%d  (%dm)   %.1fs   best %s" % [
		int(car.speed_kmh()), car.health, mini(beacon_i + 1, beacons.size()), beacons.size(),
		int(Vector2(to.x, to.z).length()), t_run, ("-" if best <= 0.0 else "%.1fs" % best)]

func _finish() -> void:
	beacon_node.visible = false
	if best <= 0.0 or t_run < best:
		best = t_run
		var cfg := ConfigFile.new()
		cfg.set_value("run", "best", best)
		cfg.save(SAVE_PATH)
	_msg("ESCAPED in %.1fs. Press R to run again." % t_run, 6.0)

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_R:
		_respawn()

# ---------- missions / hazards ----------
func _build_beacons() -> void:
	var m := _mat(Color(1.0, 0.55, 0.12), 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.1)
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.55
	beacon_node = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 120.0
	beacon_node.mesh = cm
	beacon_node.material_override = m
	add_child(beacon_node)
	for p in [Vector2(3, 3), Vector2(-3, 2), Vector2(-2, -3), Vector2(3, -2), Vector2(0, 0)]:
		beacons.append(Vector3(p.x * PITCH, 0, p.y * PITCH))

func _update_beacon() -> void:
	beacon_node.visible = true
	var b := beacons[beacon_i]
	beacon_node.position = b + Vector3(0, 60, 0)

func _build_sinkholes() -> void:
	var lava := _mat(Color(1.0, 0.35, 0.05), 0.3)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.3, 0.05)
	lava.emission_energy_multiplier = 2.5
	for p in [Vector2(2, 3), Vector2(-3, 0), Vector2(0, -2), Vector2(3, -3), Vector2(-1, 3), Vector2(1, 1)]:
		var pos := Vector3(p.x * PITCH, 0.08, p.y * PITCH)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 0.1
		mi.mesh = cm
		mi.material_override = lava
		mi.position = pos
		mi.visible = false
		add_child(mi)
		var radius := 24.0
		mi.set_meta("r", radius)
		cm.top_radius = radius
		cm.bottom_radius = radius
		sinkholes.append({"pos": pos, "radius": radius, "t": 0.0, "node": mi})

# ---------- HUD ----------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.92, 0.78))
	layer.add_child(label)
	msg = Label.new()
	msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg.position = Vector2(-300, 90)
	msg.size = Vector2(600, 40)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 28)
	msg.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
	layer.add_child(msg)

func _msg(text: String, secs: float) -> void:
	msg.text = text
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(func(): if msg.text == text: msg.text = "")
