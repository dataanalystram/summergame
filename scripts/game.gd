extends Node3D

const LANES := 7
const LANE_W := 3.2
const ROAD_HALF := LANES * LANE_W * 0.5
const ROW_D := 4.0
const SLAB_H := 0.7
const AHEAD_ROWS := 48
const BEHIND_ROWS := 10
const TOTAL_ROWS := 68
const CRACK_DIST := 165.0
const GRAVITY := 26.0
const PAINT_PER_ROW := 3
const EDGE_PER_ROW := 2

const START_SPEED := 26.0
const TOP_SPEED := 46.0
const STEER_SPEED := 12.5
const MAX_HEALTH := 3

const LIMO_PATH := "res://art/limo/3d_ee280d55825b4afbb415e5a7_1787593437008.glb"
const BROOKLYN_PATH := "res://assets/city/brooklyn-street-row-buildings-low-poly.glb"
const CITY_BLOCK_PATH := "res://assets/city/city-street-block.glb"

enum Mode { MENU, DRIVING, DYING, OVER }


class Row:
	var idx := 0
	var lane_state := PackedInt32Array()
	var lane_t := PackedFloat32Array()
	var lane_crack_total := PackedFloat32Array()
	var fall_pos := PackedVector3Array()
	var fall_vel := PackedVector3Array()
	var fall_euler := PackedVector3Array()
	var fall_spin := PackedVector3Array()
	var cracks: Array = []


class Bldg:
	var node: Node3D
	var z0 := 0.0
	var span := 300.0
	var side := 1.0
	var lean := 0.0
	var lean_speed := 1.0
	var y := -3.6
	var sway := 0.0
	var bias := 0.0


class Plate:
	var node: MeshInstance3D
	var z0 := 0.0
	var span := 46.0
	var cycle := 552.0
	var lean := 0.0
	var target_lean := 0.0
	var sink := 0.0
	var drop := 0.0


class Debris:
	var node: Node3D
	var marker: MeshInstance3D
	var marker_mat: ShaderMaterial
	var size := 1.0
	var x := 0.0
	var z := 0.0
	var y := 0.0
	var vy := 0.0
	var vx := 0.0
	var rot := Vector3.ZERO
	var spin := Vector3.ZERO
	var landed := false
	var life := 0.0


var hud
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment

var mode := Mode.MENU
var time := 0.0
var distance := 0.0
var best_distance := 0.0
var speed := 0.0
var steer := 0.0
var car_x := 0.0
var car_y := 0.0
var car_fall_vy := 0.0
var car_pitch := 0.0
var car_roll := 0.0
var plunge := false
var health := MAX_HEALTH
var invuln := 0.0
var death_t := 0.0
var over_t := 0.0
var death_cause := ""
var shake := 0.0
var debris_timer := 2.5
var setpiece_next := 600.0
var rumble_cooldown := 0.0

var rows := {}
var min_idx := 0
var max_idx := -1
var safe_lane := 3
var hole_run_left := 0
var hole_cooldown := 0
var hole_lanes: Array[int] = []
var allow_holes := false

var car_root: Node3D
var road_mm: MultiMesh
var crack_root: Node3D
var paint_mm: MultiMesh
var edge_mm: MultiMesh
var barrier_mm: MultiMesh
var debris_root: Node3D
var city_root: Node3D
var buildings: Array[Bldg] = []
var smoke_nodes: Array[Node3D] = []
var smoke_base_z: Array[float] = []
var fire_sources: Array[Node3D] = []
var debris: Array[Debris] = []
var plates: Array[Plate] = []
var fire_lights: Array[OmniLight3D] = []
var hole_light_index := 0

var asphalt_mat: StandardMaterial3D
var concrete_mat: StandardMaterial3D
var paint_mat: StandardMaterial3D
var puff_mesh: QuadMesh
var ember_material: StandardMaterial3D

var audio_collapse: AudioStreamPlayer
var audio_crash: AudioStreamPlayer
var audio_rumble: AudioStreamPlayer
var audio_engine: AudioStreamPlayer


func _ready() -> void:
	randomize()
	hud = $HUD
	cam = $Camera
	sun = $Sun
	sun.rotation_degrees = Vector3(-34.0, 40.0, 0.0)
	cam.fov = 68.0
	cam.global_position = Vector3(0.0, 4.8, 11.0)
	env = ($WorldEnvironment as WorldEnvironment).environment

	_build_materials()
	_build_road()
	_build_city()
	_build_atmosphere()
	_build_car()
	_build_audio()
	_load_best()
	_reset_run(true)
	hud.set_mode("menu")
	hud.intro_fade()


func _build_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.42
	noise.fractal_octaves = 3
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise

	asphalt_mat = StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color(0.33, 0.325, 0.32)
	asphalt_mat.albedo_texture = noise_tex
	asphalt_mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
	asphalt_mat.roughness = 0.94
	asphalt_mat.metallic_specular = 0.25
	asphalt_mat.vertex_color_use_as_albedo = true
	asphalt_mat.normal_enabled = true
	asphalt_mat.normal_texture = noise_tex
	asphalt_mat.normal_scale = 0.35

	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.58, 0.555, 0.52)
	concrete_mat.roughness = 0.92
	concrete_mat.uv1_scale = Vector3(3.0, 3.0, 3.0)
	concrete_mat.albedo_texture = noise_tex

	paint_mat = StandardMaterial3D.new()
	paint_mat.albedo_color = Color(0.87, 0.85, 0.79)
	paint_mat.roughness = 0.72

	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 64
	grad_tex.height = 64
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)

	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_mat.albedo_texture = grad_tex
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.disable_receive_shadows = true

	puff_mesh = QuadMesh.new()
	puff_mesh.size = Vector2(1.0, 1.0)
	puff_mesh.material = puff_mat

	ember_material = StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	ember_material.albedo_texture = grad_tex
	ember_material.vertex_color_use_as_albedo = true
	ember_material.albedo_color = Color(1.0, 0.55, 0.2, 1.0)


func _build_road() -> void:
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(LANE_W - 0.06, SLAB_H, ROW_D - 0.06)
	slab_mesh.material = asphalt_mat

	road_mm = MultiMesh.new()
	road_mm.transform_format = MultiMesh.TRANSFORM_3D
	road_mm.use_colors = true
	road_mm.mesh = slab_mesh
	road_mm.instance_count = TOTAL_ROWS * LANES
	var slabs := MultiMeshInstance3D.new()
	slabs.name = "Slabs"
	slabs.multimesh = road_mm
	slabs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	slabs.custom_aabb = AABB(Vector3(-200, -320, -700), Vector3(400, 500, 1000))
	add_child(slabs)

	var paint_mesh := BoxMesh.new()
	paint_mesh.size = Vector3(0.16, 0.03, 2.2)
	paint_mesh.material = paint_mat
	paint_mm = MultiMesh.new()
	paint_mm.transform_format = MultiMesh.TRANSFORM_3D
	paint_mm.mesh = paint_mesh
	paint_mm.instance_count = TOTAL_ROWS * PAINT_PER_ROW
	var paint := MultiMeshInstance3D.new()
	paint.name = "Paint"
	paint.multimesh = paint_mm
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paint.custom_aabb = AABB(Vector3(-200, -320, -700), Vector3(400, 500, 1000))
	add_child(paint)

	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.14, 0.03, 3.9)
	edge_mesh.material = paint_mat
	edge_mm = MultiMesh.new()
	edge_mm.transform_format = MultiMesh.TRANSFORM_3D
	edge_mm.mesh = edge_mesh
	edge_mm.instance_count = TOTAL_ROWS * EDGE_PER_ROW
	var edges := MultiMeshInstance3D.new()
	edges.name = "EdgePaint"
	edges.multimesh = edge_mm
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edges.custom_aabb = AABB(Vector3(-200, -320, -700), Vector3(400, 500, 1000))
	add_child(edges)

	var barrier_mesh := BoxMesh.new()
	barrier_mesh.size = Vector3(0.5, 1.0, ROW_D - 0.06)
	barrier_mesh.material = concrete_mat
	barrier_mm = MultiMesh.new()
	barrier_mm.transform_format = MultiMesh.TRANSFORM_3D
	barrier_mm.mesh = barrier_mesh
	barrier_mm.instance_count = TOTAL_ROWS * 2
	var barriers := MultiMeshInstance3D.new()
	barriers.name = "Barriers"
	barriers.multimesh = barrier_mm
	barriers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	barriers.custom_aabb = AABB(Vector3(-200, -320, -700), Vector3(400, 500, 1000))
	add_child(barriers)

	debris_root = Node3D.new()
	debris_root.name = "Debris"
	add_child(debris_root)

	crack_root = Node3D.new()
	crack_root.name = "Cracks"
	add_child(crack_root)


func _build_city() -> void:
	city_root = Node3D.new()
	city_root.name = "City"
	add_child(city_root)

	var brooklyn := load(BROOKLYN_PATH) as PackedScene
	var block := load(CITY_BLOCK_PATH) as PackedScene

	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.13, 0.105, 0.095)
	plate_mat.roughness = 1.0
	plate_mat.uv1_scale = Vector3(6.0, 6.0, 6.0)
	plate_mat.albedo_texture = NoiseTexture2D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(70.0, 2.4, 44.0)
	plate_mesh.material = plate_mat
	for side in [-1.0, 1.0]:
		for i in 12:
			var p := Plate.new()
			p.node = MeshInstance3D.new()
			p.node.mesh = plate_mesh
			p.z0 = -40.0 - i * 46.0
			p.node.position = Vector3(side * (ROAD_HALF + 40.0), -4.6, -40.0 - i * 46.0)
			p.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			city_root.add_child(p.node)
			plates.append(p)

	if brooklyn != null:
		for side in [-1.0, 1.0]:
			for i in 4:
				var z0 := -80.0 - i * 74.0 + randf_range(-6.0, 6.0)
				var s := 1.0 if i % 2 == 0 else 0.94
				var b := _make_building(brooklyn, side, side * (ROAD_HALF + 22.0 + randf_range(0.0, 2.5)), z0, s)
				b.span = 296.0
				b.node.name = "Row_%s_%d" % [str(side), i]

	if block != null:
		for side in [-1.0, 1.0]:
			var b2 := _make_building(block, side, side * (ROAD_HALF + 56.0), -60.0, 1.5)
			b2.span = 420.0
			b2.node.name = "BlockA_%s" % str(side)
			var b3 := _make_building(block, side, side * (ROAD_HALF + 58.0), -290.0, 1.4)
			b3.span = 420.0
			b3.node.name = "BlockB_%s" % str(side)
			var b4 := _make_building(block, side, side * 118.0, -420.0, 2.2)
			b4.span = 560.0
			b4.node.name = "Tower_%s" % str(side)


func _make_building(packed: PackedScene, side: float, x: float, z0: float, scale_mul: float) -> Bldg:
	var b := Bldg.new()
	b.node = Node3D.new()
	b.side = side
	b.z0 = z0
	b.y = -3.6
	b.lean_speed = randf_range(0.6, 1.4)
	b.sway = randf_range(0.0, TAU)
	b.bias = randf()
	city_root.add_child(b.node)

	var holder := Node3D.new()
	b.node.add_child(holder)
	var model := packed.instantiate()
	holder.add_child(model)
	holder.scale = Vector3(scale_mul, scale_mul, scale_mul)
	var bb := _aabb_of(holder)
	var center := bb.get_center()
	holder.position = Vector3(-center.x, -bb.position.y, -center.z)
	b.node.position = Vector3(x, b.y, distance + z0)
	b.node.rotation.y = (PI if x > 0.0 else 0.0) + randf_range(-0.05, 0.05)
	buildings.append(b)
	return b


func _build_atmosphere() -> void:
	var abyss_shader := ShaderMaterial.new()
	abyss_shader.shader = load("res://shaders/abyss.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.material = abyss_shader
	var abyss := MeshInstance3D.new()
	abyss.mesh = plane
	abyss.position = Vector3(0, -18, -260)
	abyss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(abyss)

	for i in 3:
		var fire := OmniLight3D.new()
		fire.light_color = Color(1.0, 0.42, 0.12)
		fire.light_energy = 7.0
		fire.omni_range = 20.0
		fire.position = Vector3(randf_range(-8, 8), -4.0, -40.0 - i * 60.0)
		add_child(fire)
		fire_lights.append(fire)

	var embers := GPUParticles3D.new()
	embers.amount = 45
	embers.lifetime = 3.2
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(40, 1.0, 120)
	epm.direction = Vector3(0, 1, 0)
	epm.spread = 25.0
	epm.initial_velocity_min = 2.0
	epm.initial_velocity_max = 7.0
	epm.gravity = Vector3(0.4, 1.2, 0)
	epm.scale_min = 0.12
	epm.scale_max = 0.45
	epm.color = Color(1.0, 0.55, 0.2, 0.7)
	embers.process_material = epm
	var eq := QuadMesh.new()
	eq.size = Vector2(1, 1)
	eq.material = ember_material
	embers.draw_pass_1 = eq
	embers.position = Vector3(0, -14, -120)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(embers)

	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var plume := _make_plume(side)
		var base := -40.0 - i * 46.0
		plume.position = Vector3(side * (ROAD_HALF + 7.0) + randf_range(-4, 4), 2.5, base)
		smoke_nodes.append(plume)
		smoke_base_z.append(base)

	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var anchor := Node3D.new()
		anchor.position = Vector3(side * (ROAD_HALF + randf_range(9.0, 20.0)), -1.5, -70.0 - i * 60.0)
		var fire := GPUParticles3D.new()
		fire.amount = 34
		fire.lifetime = 1.5
		fire.preprocess = 1.4
		var fpm := ParticleProcessMaterial.new()
		fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		fpm.emission_box_extents = Vector3(2.5, 0.4, 2.5)
		fpm.direction = Vector3.UP
		fpm.spread = 22.0
		fpm.initial_velocity_min = 3.0
		fpm.initial_velocity_max = 8.0
		fpm.gravity = Vector3(0.3, 3.0, 0.0)
		fpm.scale_min = 1.2
		fpm.scale_max = 3.2
		fpm.color = Color(1.0, 0.5, 0.16, 1.0)
		fire.process_material = fpm
		var fq := QuadMesh.new()
		fq.size = Vector2(1, 1)
		fq.material = ember_material
		fire.draw_pass_1 = fq
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.visibility_aabb = AABB(Vector3(-10, -6, -10), Vector3(20, 24, 20))
		anchor.add_child(fire)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.45, 0.14)
		light.light_energy = 6.0
		light.omni_range = 20.0
		light.position = Vector3(0, 2.0, 0)
		anchor.add_child(light)
		add_child(anchor)
		fire_sources.append(anchor)


func _make_plume(side: float) -> Node3D:
	var anchor := Node3D.new()
	add_child(anchor)
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 6.5
	p.preprocess = 5.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(6, 0.5, 6)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.4
	pm.gravity = Vector3(0.5 * side, 0.9, 0.6)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.scale_min = 9.0
	pm.scale_max = 22.0
	pm.color = Color(0.55, 0.48, 0.42, 0.5)
	p.process_material = pm
	p.draw_pass_1 = puff_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 60, 60))
	anchor.add_child(p)
	return anchor


func _build_car() -> void:
	car_root = Node3D.new()
	car_root.name = "Car"
	add_child(car_root)
	var packed := load(LIMO_PATH) as PackedScene
	if packed == null:
		push_warning("Limo model missing")
		return
	var holder := Node3D.new()
	holder.name = "Limo"
	car_root.add_child(holder)
	var model := packed.instantiate()
	holder.add_child(model)
	var bb := _aabb_of(holder)
	var size := bb.size
	var length := maxf(size.x, size.z)
	if size.x > size.z:
		holder.rotation_degrees.y = 90.0
	var s := 6.5 / maxf(length, 0.001)
	holder.scale = Vector3(s, s, s)
	var bb2 := _aabb_of(holder)
	var center := bb2.get_center()
	holder.position -= Vector3(center.x, bb2.position.y, center.z)
	_darken_car(model)

	for side in [-1.0, 1.0]:
		var head := SpotLight3D.new()
		head.light_color = Color(1.0, 0.86, 0.62)
		head.light_energy = 3.4
		head.spot_range = 38.0
		head.spot_angle = 27.0
		head.position = Vector3(side * 0.82, 0.78, -2.7)
		head.rotation_degrees = Vector3(-8, 0, 0)
		head.shadow_enabled = false
		car_root.add_child(head)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.42, 0.18)
	glow.light_energy = 1.1
	glow.omni_range = 6.0
	glow.position = Vector3(0, 0.4, 2.8)
	car_root.add_child(glow)


func _darken_car(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var m: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
					m.albedo_color = m.albedo_color * Color(0.85, 0.85, 0.88)
					m.metallic = maxf(m.metallic, 0.3)
					m.roughness = minf(m.roughness, 0.5)
					mi.set_surface_override_material(i, m)


func _build_audio() -> void:
	audio_collapse = _make_player("collapse", -6.0, false)
	audio_crash = _make_player("crash", -3.0, false)
	audio_rumble = _make_player("rumble", -16.0, true)
	audio_engine = _make_player("engine", -18.0, true)
	if audio_collapse.stream == null:
		audio_collapse.stream = _make_collapse_sound()
	if audio_crash.stream == null:
		audio_crash.stream = _make_crash_sound()
	if audio_rumble.stream == null:
		audio_rumble.stream = _make_rumble_sound()
	if audio_engine.stream == null:
		audio_engine.stream = _make_engine_sound()


func _wav_from(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_engine_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 2.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / rate
		var v := 0.38 * sin(TAU * 55.0 * t)
		v += 0.22 * sin(TAU * 110.0 * t + 0.4)
		v += 0.12 * sin(TAU * 165.0 * t + 1.1)
		v += 0.06 * sin(TAU * 220.0 * t + 2.0)
		v += 0.035 * sin(TAU * 330.0 * t + 0.3)
		v *= 0.85 + 0.15 * sin(TAU * 27.5 * t + 0.7)
		samples[i] = v * 0.75
	return _wav_from(samples, true)


func _make_rumble_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 4.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / rate
		var v := 0.35 * sin(TAU * 38.0 * t)
		v += 0.22 * sin(TAU * 51.0 * t + 1.0)
		v += 0.16 * sin(TAU * 19.0 * t + 2.0)
		v += 0.1 * sin(TAU * 76.0 * t + 0.5)
		v *= 0.68 + 0.32 * sin(TAU * 0.25 * t)
		samples[i] = v * 0.6
	return _wav_from(samples, true)


func _make_crash_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.9)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in count:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 7.0)
		var thump := sin(TAU * 68.0 * t) * exp(-t * 9.0)
		samples[i] = clampf(noise * 0.55 + thump * 0.55, -1.0, 1.0)
	return _wav_from(samples, false)


func _make_collapse_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 1.8)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in count:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0) * 0.4 * exp(-t * 2.2)
		var boom := sin(TAU * (58.0 - 18.0 * t) * t) * exp(-t * 1.4) * 0.55
		var grit := sin(TAU * 23.0 * t) * 0.2 * exp(-t * 1.0)
		samples[i] = clampf(noise + boom + grit, -1.0, 1.0)
	return _wav_from(samples, false)


func _make_player(key: String, db: float, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var path := "res://audio/%s.wav" % key
	if ResourceLoader.exists(path):
		var stream := load(path)
		if stream is AudioStreamWAV and loop:
			var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
			p.stream = wav
		else:
			p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _aabb_of(root: Node3D) -> AABB:
	var box := AABB()
	var has := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mb := mi.get_aabb()
			var xf := mi.global_transform
			for i in 8:
				var wp := xf * mb.get_endpoint(i)
				if not has:
					box = AABB(wp, Vector3.ZERO)
					has = true
				else:
					box = box.expand(wp)
	return box


func _lane_x(lane: int) -> float:
	return -ROAD_HALF + LANE_W * (float(lane) + 0.5)


func _lane_of(x: float) -> int:
	return clampi(int(floor((x + ROAD_HALF) / LANE_W)), 0, LANES - 1)


func _reset_run(with_holes: bool) -> void:
	allow_holes = with_holes
	for idx in rows.keys():
		_free_cracks(rows[idx])
	rows.clear()
	min_idx = -3
	max_idx = -4
	safe_lane = 3
	hole_run_left = 0
	hole_cooldown = 0
	hole_lanes.clear()
	distance = 0.0
	car_x = 0.0
	car_y = 0.0
	car_fall_vy = 0.0
	car_pitch = 0.0
	car_roll = 0.0
	steer = 0.0
	plunge = false
	health = MAX_HEALTH
	invuln = 0.0
	speed = 0.0
	debris_timer = 2.4
	setpiece_next = 550.0
	rumble_cooldown = 0.0
	for d in debris:
		if is_instance_valid(d.node):
			d.node.queue_free()
		if is_instance_valid(d.marker):
			d.marker.queue_free()
	debris.clear()
	if is_instance_valid(car_root):
		car_root.position = Vector3.ZERO
		car_root.rotation = Vector3.ZERO
	while max_idx < min_idx + TOTAL_ROWS - 1:
		max_idx += 1
		_spawn_row(max_idx)
	_update_world(0.0)
	_update_city(0.0)
	if mode == Mode.MENU:
		for idx in rows.keys():
			var row_i: int = idx
			var z := distance - float(row_i) * ROW_D
			if z < -55.0 and z > -115.0:
				var row: Row = rows[row_i]
				for lane in LANES:
					if row.lane_state[lane] == 1 and randf() < 0.5:
						row.lane_state[lane] = 2
						var ct := randf_range(0.4, 1.4)
						row.lane_crack_total[lane] = ct
						row.lane_t[lane] = ct
						_make_crack(row, lane)


func _spawn_row(idx: int) -> void:
	var row := Row.new()
	row.idx = idx
	for i in LANES:
		row.lane_state.append(0)
		row.lane_t.append(0.0)
		row.lane_crack_total.append(1.0)
		row.fall_pos.append(Vector3.ZERO)
		row.fall_vel.append(Vector3.ZERO)
		row.fall_euler.append(Vector3.ZERO)
		row.fall_spin.append(Vector3.ZERO)
	row.cracks.resize(LANES)

	var hole_start := 18 if mode == Mode.MENU else 30
	if allow_holes and idx > hole_start:
		var diff := clampf(float(idx) / 720.0, 0.0, 1.0)
		if hole_run_left > 0:
			for lane in hole_lanes:
				row.lane_state[lane] = 1
			hole_run_left -= 1
			if hole_run_left == 0:
				hole_cooldown = randi_range(2, 4)
		elif hole_cooldown > 0:
			hole_cooldown -= 1
		elif randf() < 0.5 + 0.24 * diff:
			hole_run_left = randi_range(3, 4)
			hole_lanes.clear()
			var side := -1 if safe_lane >= 4 or (safe_lane == 3 and randf() < 0.5) else 1
			var lane := safe_lane + side * 2
			if lane < 0 or lane >= LANES:
				side *= -1
				lane = safe_lane + side * 2
			hole_lanes.append(lane)
			var second := lane + side
			if second >= 0 and second < LANES and absi(second - safe_lane) >= 2:
				hole_lanes.append(second)
				var third := second + side
				if randf() < 0.45 + 0.4 * diff and third >= 0 and third < LANES and absi(third - safe_lane) >= 2:
					hole_lanes.append(third)
			if randf() < 0.3 + 0.3 * diff:
				var other := safe_lane - side * 2
				if other >= 0 and other < LANES and absi(other - safe_lane) >= 2 and not hole_lanes.has(other):
					hole_lanes.append(other)
			for l in hole_lanes:
				row.lane_state[l] = 1
			hole_run_left -= 1
			if hole_run_left == 0:
				hole_cooldown = randi_range(1, 3)
		if hole_run_left <= 0 and randf() < 0.22:
			safe_lane = clampi(safe_lane + (1 if randf() < 0.5 else -1), 1, LANES - 2)

	rows[idx] = row


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	time += delta
	invuln = maxf(0.0, invuln - delta)
	rumble_cooldown = maxf(0.0, rumble_cooldown - delta)
	shake = maxf(0.0, shake - delta * 2.6)

	if Input.is_action_just_pressed("ui_accept"):
		if mode == Mode.MENU:
			_start_run()
		elif mode == Mode.OVER and over_t > 0.6:
			_restart()
	if Input.is_action_just_pressed("restart") and mode == Mode.OVER:
		_restart()

	match mode:
		Mode.MENU:
			speed = 9.0
			_idle_audio()
			debris_timer -= delta
			if debris_timer <= 0.0:
				_spawn_debris()
				debris_timer = randf_range(2.4, 4.6)
		Mode.DRIVING:
			_process_driving(delta)
		Mode.DYING:
			_process_dying(delta)
		Mode.OVER:
			_process_over(delta)

	_update_world(delta)
	_update_city(delta)
	_update_debris(delta)
	_update_car(delta)
	_update_camera(delta)
	hud.update_stats(int(distance), speed * 3.6, int(best_distance), health)


func _process_driving(delta: float) -> void:
	var phase := clampf(distance / 2600.0, 0.0, 1.0)
	var target := lerpf(START_SPEED, TOP_SPEED, phase)
	if _braking():
		target *= 0.52
	speed = lerpf(speed, target, 1.0 - exp(-1.7 * delta))

	var dir := 0.0
	if _left():
		dir -= 1.0
	if _right():
		dir += 1.0
	steer = lerpf(steer, dir, 1.0 - exp(-8.5 * delta))
	var grip := clampf(speed / 34.0, 0.55, 1.15)
	car_x = clampf(car_x + steer * STEER_SPEED * grip * delta, -ROAD_HALF + 1.0, ROAD_HALF - 1.0)

	_check_ground()

	debris_timer -= delta
	if debris_timer <= 0.0:
		_spawn_debris()
		debris_timer = randf_range(2.2, 4.2) * lerpf(1.0, 0.45, phase)

	if distance > setpiece_next:
		setpiece_next += randf_range(480.0, 720.0)
		_setpiece()

	if audio_engine.stream != null:
		if not audio_engine.playing:
			audio_engine.play()
		audio_engine.volume_db = -18.0
		audio_engine.pitch_scale = lerpf(0.75, 1.25, clampf(speed / TOP_SPEED, 0.0, 1.0))
	if audio_rumble.stream != null and not audio_rumble.playing:
		audio_rumble.play()


func _idle_audio() -> void:
	if audio_engine.stream != null and not audio_engine.playing:
		audio_engine.play()
	audio_engine.volume_db = -26.0
	audio_engine.pitch_scale = 0.7
	if audio_rumble.stream != null and not audio_rumble.playing:
		audio_rumble.play()


func _process_dying(delta: float) -> void:
	death_t += delta
	speed = maxf(0.0, speed - 26.0 * delta)
	steer = lerpf(steer, 0.0, 1.0 - exp(-3.0 * delta))
	car_roll = lerpf(car_roll, 0.0, 1.0 - exp(-2.0 * delta))
	if plunge:
		car_fall_vy -= GRAVITY * 1.25 * delta
		car_y = maxf(car_y + car_fall_vy * delta, -12.5)
		car_pitch += 1.6 * delta
		car_root.rotation.z = sin(death_t * 5.0) * 0.22
	else:
		car_root.rotation.y = sin(death_t * 5.0) * 0.55 * (1.0 - death_t * 0.6)
	if death_t > 1.7:
		_finish_death()


func _process_over(delta: float) -> void:
	over_t += delta
	speed = maxf(0.0, speed - 12.0 * delta)
	if plunge and car_y > -12.5:
		car_fall_vy -= GRAVITY * 1.1 * delta
		car_y = maxf(car_y + car_fall_vy * delta, -12.5)


func _check_ground() -> void:
	var lane := _lane_of(car_x)
	var front_idx := int(roundf((distance + 1.4) / ROW_D))
	var row: Row = rows.get(front_idx)
	if row != null and row.lane_state[lane] >= 3:
		_die("ground")


func _die(cause: String) -> void:
	if mode != Mode.DRIVING:
		return
	mode = Mode.DYING
	death_cause = cause
	death_t = 0.0
	shake = 1.2
	if audio_engine != null:
		audio_engine.stop()
	if audio_rumble != null:
		audio_rumble.stop()
	hud.set_mode("dying")
	if cause == "ground":
		plunge = true
		car_fall_vy = -3.0
		_play(audio_collapse, -2.0)
	else:
		plunge = false
		car_fall_vy = 0.0
		_play(audio_crash, 0.0)
		_burst_puff(Vector3(car_x, 0.8, 0.0), 1.6)


func _finish_death() -> void:
	mode = Mode.OVER
	over_t = 0.0
	if distance > best_distance:
		best_distance = distance
		_save_best()
	hud.show_over(death_cause, int(distance), int(best_distance))
	hud.set_best(int(best_distance))


func _update_world(delta: float) -> void:
	distance += speed * delta
	var base_idx := int(floor(distance / ROW_D))
	while max_idx < base_idx + AHEAD_ROWS:
		max_idx += 1
		_spawn_row(max_idx)
	while min_idx < base_idx - BEHIND_ROWS:
		_free_cracks(rows[min_idx])
		rows.erase(min_idx)
		min_idx += 1

	for idx in rows.keys():
		var row: Row = rows[idx]
		_update_row_state(row, delta)
		_place_row(row)

	_update_paint()


func _update_row_state(row: Row, delta: float) -> void:
	var z := distance - row.idx * ROW_D
	for lane in LANES:
		var st := row.lane_state[lane]
		if st == 1:
			if z > -CRACK_DIST and (mode != Mode.MENU or z < -35.0):
				row.lane_state[lane] = 2
				row.lane_crack_total[lane] = randf_range(1.0, 1.8)
				row.lane_t[lane] = row.lane_crack_total[lane]
				_make_crack(row, lane)
		elif st == 2:
			row.lane_t[lane] -= delta
			if row.lane_t[lane] <= 0.0:
				row.lane_state[lane] = 3
				row.fall_pos[lane] = Vector3(_lane_x(lane), -SLAB_H * 0.5, z)
				row.fall_vel[lane] = Vector3(randf_range(-1.6, 1.6), randf_range(-2.4, -0.4), 0.0)
				row.fall_euler[lane] = Vector3.ZERO
				row.fall_spin[lane] = Vector3(randf_range(-0.9, 0.9), randf_range(-0.5, 0.5), randf_range(-0.9, 0.9))
				if absf(z) < 70.0 and rumble_cooldown <= 0.0:
					rumble_cooldown = 0.45
					shake = maxf(shake, 0.28)
					_play(audio_collapse, -8.0)
				if absf(z) < 90.0:
					_burst_puff(Vector3(_lane_x(lane), 0.2, z), 0.9)
					_light_hole(Vector3(_lane_x(lane), -4.0, z))
					_burst_embers(Vector3(_lane_x(lane), -0.1, z))
		elif st == 3:
			var v := row.fall_vel[lane]
			v.y -= GRAVITY * delta
			row.fall_vel[lane] = v
			var p := row.fall_pos[lane] + v * delta
			row.fall_pos[lane] = p
			var e := row.fall_euler[lane] + row.fall_spin[lane] * delta
			row.fall_euler[lane] = e
			if p.y < -70.0:
				row.lane_state[lane] = 4


func _place_row(row: Row) -> void:
	var z := distance - row.idx * ROW_D
	var base_slot := posmod(row.idx, TOTAL_ROWS) * LANES
	for lane in LANES:
		var st := row.lane_state[lane]
		var slot := base_slot + lane
		if st == 4:
			var cr_hide = row.cracks[lane]
			if cr_hide != null and is_instance_valid(cr_hide):
				cr_hide.visible = false
			road_mm.set_instance_transform(slot, _hidden())
			continue
		var pos := Vector3(_lane_x(lane), -SLAB_H * 0.5, z)
		var slab_basis := Basis()
		var crack_intensity := 0.0
		if st == 2:
			var k := 1.0 - clampf(row.lane_t[lane] / maxf(row.lane_crack_total[lane], 0.01), 0.0, 1.0)
			var jitter := 0.03 + 0.09 * k
			pos.x += sin(time * 31.0 + lane * 2.3 + row.idx) * jitter
			pos.y += absf(sin(time * 23.0 + lane * 1.7 + row.idx)) * jitter * 0.7
			slab_basis = Basis(Vector3.FORWARD, sin(time * 19.0 + lane) * 0.018 * k)
			slab_basis = slab_basis * Basis(Vector3.RIGHT, cos(time * 17.0 + row.idx) * 0.012 * k)
			crack_intensity = 0.12 + 0.88 * k
		elif st == 3:
			pos = row.fall_pos[lane]
			slab_basis = Basis.from_euler(row.fall_euler[lane])
			crack_intensity = 0.75
		var tint := 0.78 + float(posmod(row.idx * 7 + lane * 13, 23)) / 23.0 * 0.22
		road_mm.set_instance_color(slot, Color(tint, tint, tint * 0.99))
		road_mm.set_instance_transform(slot, Transform3D(slab_basis, pos))
		var cr = row.cracks[lane]
		if cr != null and is_instance_valid(cr):
			var mat: ShaderMaterial = cr.material_override
			mat.set_shader_parameter("intensity", crack_intensity)
			cr.transform = Transform3D(slab_basis, pos + slab_basis * Vector3(0.0, SLAB_H * 0.5 + 0.035, 0.0))

	var barrier_slot := posmod(row.idx, TOTAL_ROWS) * 2
	for side in 2:
		var lane := 0 if side == 0 else LANES - 1
		var x := -ROAD_HALF - 0.25 if side == 0 else ROAD_HALF + 0.25
		if row.lane_state[lane] >= 3:
			barrier_mm.set_instance_transform(barrier_slot + side, _hidden())
		else:
			barrier_mm.set_instance_transform(barrier_slot + side, Transform3D(Basis(), Vector3(x, 0.5, z)))


func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -500, 0))


func _make_crack(row: Row, lane: int) -> void:
	if row.cracks[lane] != null:
		return
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LANE_W * 0.97, ROW_D * 0.97)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crack.gdshader")
	mat.set_shader_parameter("intensity", 0.0)
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack_root.add_child(mi)
	row.cracks[lane] = mi


func _free_cracks(row: Row) -> void:
	for cr in row.cracks:
		if cr != null and is_instance_valid(cr):
			cr.queue_free()
	row.cracks.clear()


func _update_paint() -> void:
	var boundaries := [1, 3, 5]
	for idx in rows.keys():
		var row: Row = rows[idx]
		var z := distance - row.idx * ROW_D
		var base_slot := posmod(row.idx, TOTAL_ROWS) * PAINT_PER_ROW
		for k in 3:
			var b: int = boundaries[k]
			var slot := base_slot + k
			if row.lane_state[b] >= 3 or row.lane_state[b + 1] >= 3:
				paint_mm.set_instance_transform(slot, _hidden())
			else:
				var x := -ROAD_HALF + float(b + 1) * LANE_W
				paint_mm.set_instance_transform(slot, Transform3D(Basis(), Vector3(x, 0.02, z)))
		var edge_base := posmod(row.idx, TOTAL_ROWS) * EDGE_PER_ROW
		if row.lane_state[0] >= 3:
			edge_mm.set_instance_transform(edge_base, _hidden())
		else:
			edge_mm.set_instance_transform(edge_base, Transform3D(Basis(), Vector3(-ROAD_HALF + 0.35, 0.02, z)))
		if row.lane_state[LANES - 1] >= 3:
			edge_mm.set_instance_transform(edge_base + 1, _hidden())
		else:
			edge_mm.set_instance_transform(edge_base + 1, Transform3D(Basis(), Vector3(ROAD_HALF - 0.35, 0.02, z)))


func _update_city(delta: float) -> void:
	var phase := clampf(distance / 3000.0, 0.0, 1.0)
	for b in buildings:
		var z := distance + b.z0
		if z > 140.0:
			b.z0 -= b.span
			z = distance + b.z0
		var target := -b.side * (0.02 + phase * 0.3 * (0.4 + b.bias)) * b.lean_speed
		b.lean = lerpf(b.lean, target, 1.0 - exp(-0.7 * delta))
		b.sway += delta * 0.25
		b.node.position = Vector3(b.node.position.x, b.y - phase * (0.5 + b.bias * 4.0), z)
		b.node.rotation.z = b.lean + sin(b.sway) * 0.01 * (1.0 + phase * 2.0)
		b.node.rotation.x = sin(b.sway * 0.7 + 1.0) * 0.004
	for p in plates:
		var pz := distance + p.z0
		if pz > 100.0:
			p.z0 -= p.cycle
			pz = distance + p.z0
			p.target_lean = randf_range(-0.05, 0.05)
		p.node.position = Vector3(p.node.position.x, -4.6 - p.sink - p.drop, pz)
		p.lean = lerpf(p.lean, p.target_lean, 1.0 - exp(-0.6 * delta))
		p.node.rotation.z = p.lean
		p.node.rotation.x = p.lean * 0.4
	for i in smoke_nodes.size():
		smoke_nodes[i].position.z = distance + smoke_base_z[i]
	for i in fire_sources.size():
		var anchor := fire_sources[i]
		anchor.position.z += speed * delta
		if anchor.position.z > 60.0:
			anchor.position.z -= 380.0
		var lt := anchor.get_child(1) as OmniLight3D
		if lt != null:
			lt.light_energy = 5.0 + sin(time * 9.0 + float(i)) * 1.8
	for i in fire_lights.size():
		var fl := fire_lights[i]
		fl.position.z += speed * delta
		if fl.position.z > 40.0:
			fl.position = Vector3(randf_range(-9.0, 9.0), -4.0, -200.0 - randf_range(0.0, 80.0))
			fl.light_energy = 5.0
	env.fog_density = 0.0045 + phase * 0.0025
	sun.light_energy = 2.4 - phase * 0.5


func _setpiece() -> void:
	shake = maxf(shake, 0.5)
	_play(audio_collapse, -1.0)
	hud.flash(0.16)
	for b in buildings:
		if randf() < 0.4:
			b.lean_speed = randf_range(2.0, 5.0)
	for p in plates:
		if randf() < 0.3:
			p.target_lean = randf_range(-0.32, 0.32)
			p.drop = randf_range(0.5, 2.5)
	for i in 2:
		_spawn_debris()


func _spawn_debris() -> void:
	var phase := clampf(distance / 2600.0, 0.0, 1.0)
	var d := Debris.new()
	var lane := randi_range(0, LANES - 1)
	d.x = _lane_x(lane) + randf_range(-1.1, 1.1)
	d.z = -randf_range(85.0, 135.0)
	d.size = randf_range(1.3, 3.0)
	d.y = randf_range(28.0, 44.0)
	d.vy = -6.0 - 8.0 * phase
	d.vx = randf_range(-1.6, 1.6)
	d.spin = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))

	d.node = Node3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(d.size, d.size * randf_range(0.6, 1.1), d.size * randf_range(0.8, 1.4))
	mesh.material = concrete_mat
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	d.node.add_child(mi)
	d.node.position = Vector3(d.x, d.y, d.z)
	debris_root.add_child(d.node)

	d.marker = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(d.size * 2.0, d.size * 2.0)
	d.marker.mesh = qm
	var mark_mat := ShaderMaterial.new()
	mark_mat.shader = load("res://shaders/warn_marker.gdshader")
	d.marker_mat = mark_mat
	d.marker.material_override = mark_mat
	d.marker.rotation_degrees.x = -90.0
	d.marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.marker.position = Vector3(d.x, 0.06, d.z)
	debris_root.add_child(d.marker)
	debris.append(d)


func _update_debris(delta: float) -> void:
	var keep: Array[Debris] = []
	for d in debris:
		if not is_instance_valid(d.node):
			continue
		d.life += delta
		d.z += speed * delta
		d.node.position.z = d.z
		if is_instance_valid(d.marker):
			d.marker.position.z = d.z
		if not d.landed:
			d.vy -= GRAVITY * delta
			d.y += d.vy * delta
			d.x += d.vx * delta
			d.node.position.x = d.x
			d.node.position.y = d.y
			d.rot += d.spin * delta
			d.node.rotation = d.rot
			if is_instance_valid(d.marker):
				d.marker.position.x = d.x
			var closeness := clampf((42.0 - d.y) / 42.0, 0.0, 1.0)
			if is_instance_valid(d.marker):
				d.marker.scale = Vector3.ONE * lerpf(0.55, 1.15, closeness)
			d.marker_mat.set_shader_parameter("intensity", 0.25 + closeness * 0.9)
			if d.y <= d.size * 0.5 + 0.1:
				d.landed = true
				d.y = d.size * 0.5
				d.node.position.y = d.y
				_burst_puff(Vector3(d.x, 0.5, d.z), d.size * 0.8)
				if mode == Mode.DRIVING and absf(d.z) < 4.5 and absf(d.x - car_x) < 1.9 + d.size * 0.4:
					_hit_debris(d)
				elif absf(d.z) < 45.0:
					shake = maxf(shake, 0.25)
				if is_instance_valid(d.marker):
					d.marker.queue_free()
		elif d.life > 1.4:
			d.node.queue_free()
			continue
		keep.append(d)
	debris = keep


func _hit_debris(_d: Debris) -> void:
	if invuln > 0.0:
		return
	health -= 1
	invuln = 1.4
	shake = 0.9
	hud.flash(0.55)
	_burst_puff(Vector3(car_x, 1.0, 0.0), 1.4)
	_play(audio_crash, 0.0)
	speed *= 0.55
	if health <= 0:
		_die("debris")


func _burst_puff(pos: Vector3, scale_mul: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.5
	p.one_shot = true
	p.explosiveness = 0.95
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 3.0 * scale_mul
	pm.initial_velocity_max = 9.0 * scale_mul
	pm.gravity = Vector3(0, -1.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 1.4 * scale_mul
	pm.scale_max = 3.4 * scale_mul
	pm.color = Color(0.45, 0.36, 0.29, 0.65)
	p.process_material = pm
	p.draw_pass_1 = puff_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.2).timeout.connect(p.queue_free)


func _burst_embers(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 22
	p.lifetime = 1.5
	p.one_shot = true
	p.explosiveness = 0.9
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 45.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, 2.5, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.9
	pm.color = Color(1.0, 0.55, 0.2, 1.0)
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	qm.material = ember_material
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func _light_hole(pos: Vector3) -> void:
	if fire_lights.is_empty():
		return
	var l: OmniLight3D = fire_lights[hole_light_index % fire_lights.size()]
	hole_light_index += 1
	l.position = pos
	l.light_energy = 11.0


func _update_car(delta: float) -> void:
	if not is_instance_valid(car_root):
		return
	if mode == Mode.DRIVING:
		var target_roll := -steer * 0.075
		car_roll = lerpf(car_roll, target_roll, 1.0 - exp(-7.0 * delta))
		car_root.rotation.y = lerpf(car_root.rotation.y, -steer * 0.13, 1.0 - exp(-7.0 * delta))
		car_root.rotation.x = lerpf(car_root.rotation.x, sin(time * 2.3) * 0.004, 0.2)
		car_root.rotation.z = car_roll
	elif mode == Mode.OVER and not plunge:
		car_root.rotation.z = lerpf(car_root.rotation.z, 0.0, 0.05)
	car_root.position = Vector3(car_x, car_y + sin(time * 9.0) * 0.006, 0.0)


func _update_camera(delta: float) -> void:
	var target_pos: Vector3
	var target_look: Vector3
	if mode == Mode.MENU:
		target_pos = Vector3(5.4 + sin(time * 0.12) * 0.9, 3.5 + sin(time * 0.19) * 0.15, 9.4)
		target_look = Vector3(-0.7, 1.0, -13.0)
	else:
		var fy := maxf(car_y, -9.0)
		if plunge and (mode == Mode.DYING or mode == Mode.OVER):
			target_pos = Vector3(car_x * 0.4, 7.6, 11.8)
			target_look = Vector3(car_x * 0.7, clampf(fy * 0.55, -6.0, 0.6), -9.0)
		else:
			target_pos = Vector3(car_x * 0.5, 4.2 + fy * 0.22, 10.2)
			target_look = Vector3(car_x * 0.8, 0.8 + fy * 0.55, -18.0)
		cam.fov = lerpf(cam.fov, 66.0 + clampf(speed / TOP_SPEED, 0.0, 1.0) * 8.0, 1.0 - exp(-2.0 * delta))
	var shake_off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25
	cam.global_position = cam.global_position.lerp(target_pos, 1.0 - exp(-6.0 * delta)) + shake_off
	if cam.global_position.distance_to(target_look) > 0.05:
		cam.look_at(target_look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER:
			if mode == Mode.MENU:
				_start_run()
			elif mode == Mode.OVER and over_t > 0.6:
				_restart()
		elif k == KEY_R and mode == Mode.OVER:
			_restart()


func _start_run() -> void:
	_reset_run(true)
	speed = START_SPEED
	mode = Mode.DRIVING
	hud.set_mode("play")
	hud.fade_in()
	if audio_engine.stream != null:
		audio_engine.play()
	if audio_rumble.stream != null:
		audio_rumble.play()


func _restart() -> void:
	_reset_run(true)
	speed = START_SPEED
	mode = Mode.DRIVING
	hud.set_mode("play")
	hud.fade_in()


func _left() -> bool:
	return Input.is_action_pressed("steer_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)


func _right() -> bool:
	return Input.is_action_pressed("steer_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)


func _braking() -> bool:
	return Input.is_action_pressed("brake") or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)


func _play(player: AudioStreamPlayer, volume: float = 0.0) -> void:
	if player == null or player.stream == null:
		return
	player.volume_db = volume
	player.play()


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://run.cfg") == OK:
		best_distance = float(cfg.get_value("run", "best", 0.0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best", best_distance)
	cfg.save("user://run.cfg")


func debug_info() -> Dictionary:
	var out := {
		"mode": mode,
		"distance": distance,
		"speed": speed,
		"allow_holes": allow_holes,
		"rows": rows.size(),
		"min_idx": min_idx,
		"max_idx": max_idx,
		"hole_run_left": hole_run_left,
		"hole_cooldown": hole_cooldown,
		"health": health,
		"debris": debris.size(),
		"cracks": crack_root.get_child_count(),
		"engine_stream": audio_engine.stream != null,
		"engine_playing": audio_engine.playing,
		"rumble_playing": audio_rumble.playing,
	}
	var holed := 0
	var falling := 0
	var cracked := 0
	for idx in rows.keys():
		var r: Row = rows[idx]
		for i in LANES:
			if r.lane_state[i] >= 1:
				holed += 1
			if r.lane_state[i] == 2:
				cracked += 1
			if r.lane_state[i] >= 3:
				falling += 1
	out["holed"] = holed
	out["cracked"] = cracked
	out["fallen"] = falling
	return out
