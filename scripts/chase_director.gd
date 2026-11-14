extends Node3D
class_name ChaseDirector
# Act 3 of the film breakdown (clip 2:15-4:55): the limo escape down one avenue.
# Owns the set-pieces, the chasing dust wave, ramps/gaps and the cinematic camera cuts.

const START_Z := 480.0
const END_P := 900.0
const AVENUE_X := 0.0
const ROAD_HALF := 8.0
const WAVE_START_GAP := 70.0
const CAR_MODELS := "res://assets/packs/cars/FBX/"
const PALM := "res://assets/packs/nature/BigPalmTree.glb"
const PALM_S := "res://assets/packs/nature/SmallPalmTree.glb"

var world   # open_world.gd
var active := false
var auto_cams := true
var manual_cam := ""
var cam_mode := "chase"
var cam_until := 0.0
var t := 0.0
var quake := 0.0
var beats: Array[Dictionary] = []
var next_beat := 0

var ramps: Array[Dictionary] = []   # {p0,p1,h,x0,x1}
var gaps: Array[Dictionary] = []    # {p0,p1,x0,x1,on}
var wave_p := -WAVE_START_GAP
var wave_speed := 18.0
var wave: Node3D
var wave_puffs: Array[MeshInstance3D] = []
var movers: Array[Dictionary] = []  # {node, vel, life, spin}
var tower_pivot: Node3D
var tower: FallenTower
var overpass: Node3D
var smoke_mat: StandardMaterial3D
var bars: Array[ColorRect] = []
var shake_t := 0.0
var failed := false
var rolling := false
var palm_mat: StandardMaterial3D
var people: Array[PackedScene] = []
var runners: Array[Dictionary] = []
const PEOPLE_DIR := "res://assets/packs/people/"

# ---------------------------------------------------------------- setup
func setup(w) -> void:
	world = w
	smoke_mat = _smoke_material(Color(0.66, 0.56, 0.44, 0.9))
	_build_palms_and_curb_cars()
	_build_ramps()
	_build_overpass()
	_build_tower()
	_build_downtown()
	_build_wave()
	_build_letterbox()
	for f in DirAccess.get_files_at(PEOPLE_DIR):
		if f.ends_with(".fbx"):
			people.append(load(PEOPLE_DIR + f))
	beats = [
		{"p": 2.0, "cam": "wide", "dur": 3.0, "act": "start"},
		{"p": 55.0, "cam": "top", "dur": 3.0, "act": "cracks"},
		{"p": 115.0, "cam": "rear", "dur": 2.6, "act": ""},
		{"p": 160.0, "cam": "side", "dur": 2.6, "act": "house"},
		{"p": 205.0, "cam": "driver", "dur": 3.0, "act": "taxi"},
		{"p": 252.0, "cam": "side_low", "dur": 2.4, "act": "ramp"},
		{"p": 330.0, "cam": "backseat", "dur": 2.6, "act": ""},
		{"p": 380.0, "cam": "top", "dur": 3.0, "act": "tilt"},
		{"p": 470.0, "cam": "chase", "dur": 0.0, "act": "split"},
		{"p": 505.0, "cam": "side_low", "dur": 2.4, "act": ""},
		{"p": 575.0, "cam": "wide", "dur": 2.6, "act": "overpass"},
		{"p": 548.0, "cam": "", "dur": 0.0, "act": "tower"},
		{"p": 742.0, "cam": "", "dur": 0.0, "act": "facade"},
		{"p": 820.0, "cam": "rear", "dur": 2.4, "act": ""},
		{"p": END_P, "cam": "chase", "dur": 0.0, "act": "escape"},
	]

func start() -> void:
	active = true
	t = 0.0
	next_beat = 0
	wave_p = -WAVE_START_GAP
	wave_speed = 18.0
	failed = false
	rolling = false
	_set_bars(true)
	world._msg("Hold W to drive", 30.0)

func progress() -> float:
	return START_Z - world.car.global_position.z

# Ground model used by CityCar through world.ground_height_at.
func height_at(x: float, z: float) -> float:
	var p := START_Z - z
	for g in gaps:
		if g.on and p >= g.p0 and p <= g.p1 and x >= g.x0 and x <= g.x1:
			return -14.0
	var h := 0.0
	for r in ramps:
		if p >= r.p0 and p <= r.p1 and x >= r.x0 and x <= r.x1:
			h = maxf(h, r.h * (p - r.p0) / (r.p1 - r.p0))
	return h

# ---------------------------------------------------------------- per frame
func update(delta: float) -> void:
	if not active:
		return
	t += delta
	var car: CityCar = world.car
	var p := progress()
	quake = clampf(0.35 + 0.65 * sin(t * 0.7) * sin(t * 0.31), 0.25, 1.0)
	# beats
	while next_beat < beats.size() and p >= beats[next_beat].p:
		_run_beat(beats[next_beat])
		next_beat += 1
	# ramps: launch when leaving a lip at speed
	for r in ramps:
		if not car.airborne and absf(car.global_position.x - (r.x0 + r.x1) * 0.5) < (r.x1 - r.x0) * 0.5 \
				and p >= r.p1 - 0.5 and p <= r.p1 + 3.0 and car.speed > 12.0 and not r.get("used", false):
			r["used"] = true
			car.launch(car.speed * r.h / (r.p1 - r.p0) * 1.15 + 3.0)
			Engine.time_scale = 0.45
			if auto_cams and manual_cam == "":
				_cut("side_low", 1.4)
			world._msg("HOLD ON!", 1.2)
	if car.airborne == false and Engine.time_scale < 1.0:
		Engine.time_scale = 1.0
	# dust wave: starts rolling once the player puts their foot down
	if not rolling:
		if car.speed > 4.0:
			rolling = true
			wave_p = p - WAVE_START_GAP
			world._msg("", 0.1)
		else:
			wave_p = p - WAVE_START_GAP
	wave_speed = minf(wave_speed + delta * 0.9, 38.0)
	wave_p += wave_speed * delta
	wave_p = maxf(wave_p, p - 140.0)   # never falls hopelessly behind: it is a chase
	wave.global_position = Vector3(AVENUE_X, 0, START_Z - wave_p)
	for i in wave_puffs.size():
		var m := wave_puffs[i]
		var s := 1.0 + 0.15 * sin(t * 1.3 + i)
		m.scale = Vector3(s, s, s)
	var behind := p - wave_p
	if rolling and behind < 2.0 and not failed:
		_fail("SWALLOWED BY THE DUST")
	if car.falling and car.global_position.y < -6.0 and not failed:
		_fail("THE ROAD TOOK YOU")
	if car.dead and not failed:
		_fail("WRECKED")
	_update_movers(delta)
	_update_runners(delta)
	tower.update(delta, car.global_position)
	_update_camera(delta)
	world.label.text = "%d km/h    HP %d    DUST %dm behind    %dm to go    [C] camera  [V] jump-cam %s" % [
		int(car.speed_kmh()), car.health, int(maxf(behind, 0.0)), int(maxf(END_P - p, 0.0)), ("on" if auto_cams else "off")]

func _fail(why: String) -> void:
	failed = true
	Engine.time_scale = 1.0
	world._msg(why + " - restarting", 2.0)
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()

func handle_key(code: int) -> void:
	var order := ["chase", "driver", "backseat", "rear", "side", "side_low", "top", "wide"]
	if code == KEY_C:
		var i := order.find(manual_cam if manual_cam != "" else cam_mode)
		manual_cam = order[(i + 1) % order.size()]
		world._msg("Camera: " + manual_cam, 1.0)
	elif code == KEY_V:
		auto_cams = not auto_cams
		manual_cam = ""

# ---------------------------------------------------------------- beats
func _run_beat(b: Dictionary) -> void:
	pass   # camera stays on the player's chase view; only jumps cut (see launch below)
	_spawn_crowd(b.p + 60.0, 14)
	match b.act:
		"start":
			world._msg("EARTHQUAKE! DRIVE!", 2.5)
			shake_t = 2.0
		"cracks":
			_spawn_cracks(70.0, 250.0, 34)
			_open_fissure(80.0, 210.0, 12.0, 16.0)
		"house":
			_collapse_building_near(185.0, 1)
			_collapse_building_near(200.0, -1)
		"taxi":
			_spawn_oncoming(world.car.global_position.z - 110.0)
		"ramp":
			shake_t = 1.0
		"tilt":
			_tilt_buildings(380.0, 500.0)
		"split":
			world._msg("THE ROAD IS SPLITTING - KEEP RIGHT!", 2.5)
			gaps[2].on = true
			gaps[2]["node"].visible = true
			shake_t = 1.5
		"overpass":
			pass
		"tower":
			_drop_tower()
		"facade":
			_facade_rain()
		"escape":
			active = false
			Engine.time_scale = 1.0
			_set_bars(false)
			wave.visible = false
			world.on_chase_escaped()

func _cut(mode: String, dur: float) -> void:
	cam_mode = mode
	cam_until = t + dur
	_snap_camera()

# ---------------------------------------------------------------- camera
func _rig() -> Array:   # [origin, look_at]
	var car: CityCar = world.car
	var c := car.global_position
	var f := car.forward_vector()
	var r := Vector3(cos(car.heading), 0, -sin(car.heading))
	var up := Vector3.UP
	var mode := manual_cam if manual_cam != "" else cam_mode
	match mode:
		"driver":      # over the driver's shoulder, looking out the windshield
			return [c + up * 1.12 - r * 0.45 + f * 0.6, c + up * 1.0 + f * 20.0]
		"backseat":    # rear seat, sees the cabin and the road ahead
			return [c + up * 1.15 + r * 0.35 - f * 1.4, c + up * 1.0 + f * 15.0]
		"rear":        # looking back through the rear window at the dust wave
			return [c + up * 1.2 - f * 0.4, c + up * 1.6 - f * 30.0]
		"windshield_up":
			return [c + up * 1.4 + f * 3.9 + r * 0.6, tower_pivot.global_position + Vector3(-20.0, 70.0, 0)]
		"side":        # tracking alongside at road level
			return [c + r * 7.5 + up * 1.6 + f * 2.0, c + up * 1.0]
		"side_low":
			return [c - r * 6.0 + up * 0.5 + f * 4.0, c + up * 1.4 - f * 1.0]
		"top":         # drone straight down, slightly ahead
			return [c + up * 48.0 + f * 8.0, c + f * 10.0]
		"wide":        # static shot down the street from ahead, looking back at the limo
			return [Vector3(AVENUE_X + 5.5, 2.2, c.z) + f * 55.0, c + up * 1.2]
		_:
			return [c - f * 11.5 + up * 4.6, c + up * 1.5 + f * 8.0]

func _snap_camera() -> void:
	var rg := _rig()
	world.cam.global_position = rg[0]
	world.cam.look_at(rg[1])

func _update_camera(delta: float) -> void:
	if manual_cam == "" and cam_mode != "chase" and t > cam_until:
		cam_mode = "chase"
		_snap_camera()
	var mode := manual_cam if manual_cam != "" else cam_mode
	var rg := _rig()
	var cam: Camera3D = world.cam
	var ud := delta / maxf(Engine.time_scale, 0.01)
	if mode == "wide":
		# a locked-off camera: stays put once placed, only pans to follow
		if cam.global_position.distance_to(world.car.global_position) > 140.0:
			_snap_camera()
		cam.look_at(rg[1])
	elif mode == "chase" or mode == "top":
		cam.global_position = cam.global_position.lerp(rg[0], 1.0 - exp(-6.0 * ud))
		cam.look_at(rg[1])
	else:
		cam.global_position = rg[0]
		cam.look_at(rg[1])
	# handheld + quake shake
	shake_t = maxf(shake_t - delta, 0.0)
	var amp := 0.03 + 0.06 * quake + 0.18 * shake_t
	if mode in ["driver", "backseat", "rear", "windshield_up"]:
		amp *= 0.6
	cam.global_position += Vector3(sin(t * 37.0) * amp, sin(t * 43.0 + 1.0) * amp, sin(t * 29.0 + 2.0) * amp * 0.5)
	cam.rotation.z += sin(t * 17.0) * amp * 0.08
	cam.fov = lerpf(cam.fov, 58.0 if mode in ["driver", "backseat", "rear", "windshield_up"] else 64.0 + world.car.speed * 0.2, 1.0 - exp(-4.0 * ud))

# ---------------------------------------------------------------- set dressing
func _smoke_material(c: Color) -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 4.0
	return m

func _palm(path: String, pos: Vector3, h: float) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		return
	var holder: Node3D = world._place_fit(ps, pos, h * 0.45, randf() * TAU, false)
	holder.set_meta("palm", true)
	if palm_mat == null:
		palm_mat = StandardMaterial3D.new()
		palm_mat.albedo_texture = load("res://assets/packs/nature/PalmTree.png")
		palm_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_apply_mat(holder, palm_mat)

func _apply_mat(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_apply_mat(c, m)

func _build_palms_and_curb_cars() -> void:
	var z := START_Z - 10.0
	var i := 0
	while z > -START_Z:
		_palm(PALM if i % 3 else PALM_S, Vector3(AVENUE_X - 10.5, 0, z), 15.0)
		_palm(PALM_S if i % 2 else PALM, Vector3(AVENUE_X + 10.5, 0, z - 9.0), 14.0)
		z -= 22.0
		i += 1
	var models: Array[PackedScene] = []
	for f in DirAccess.get_files_at(CAR_MODELS):
		if f.ends_with(".fbx"):
			models.append(load(CAR_MODELS + f))
	if models.is_empty():
		return
	var p := 40.0
	while p < END_P:
		var in_ramp := (p > 240 and p < 330) or (p > 495 and p < 575)
		if not in_ramp:
			var side := -1.0 if int(p) % 2 == 0 else 1.0
			var hc: Node3D = world._place_fit(models[int(p) % models.size()], Vector3(AVENUE_X + side * 6.6, 0, START_Z - p), 4.6, randf_range(-0.1, 0.1))
			hc.set_meta("fit", true)
		p += randf_range(26.0, 48.0)

func _slab(pos: Vector3, size: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos
	mi.rotation = rot
	return mi

func _build_ramps() -> void:
	var asphalt: Material = world._mat(Color(0.09, 0.09, 0.095), 0.85)
	var dirt: Material = world._mat(Color(0.24, 0.18, 0.13), 1.0)
	# ramp 1: whole road heaves, then a crossing gap
	ramps.append({"p0": 270.0, "p1": 288.0, "h": 3.2, "x0": -ROAD_HALF, "x1": ROAD_HALF})
	gaps.append({"p0": 289.0, "p1": 303.0, "x0": -40.0, "x1": 40.0, "on": true})
	# ramp 2: right half heaves, left half has already dropped
	ramps.append({"p0": 522.0, "p1": 540.0, "h": 3.6, "x0": -1.5, "x1": ROAD_HALF})
	gaps.append({"p0": 541.0, "p1": 556.0, "x0": -40.0, "x1": 40.0, "on": true})
	gaps.append({"p0": 495.0, "p1": 521.0, "x0": -ROAD_HALF - 2.0, "x1": -1.8, "on": false})
	for r in ramps:
		var ln: float = r.p1 - r.p0
		var w: float = r.x1 - r.x0
		var ang := atan2(r.h, ln)
		var cz: float = START_Z - (r.p0 + r.p1) * 0.5
		_slab(Vector3((r.x0 + r.x1) * 0.5, r.h * 0.5 - 0.35, cz), Vector3(w, 0.7, sqrt(ln * ln + r.h * r.h)), Vector3(ang, 0, 0), asphalt)
		_slab(Vector3((r.x0 + r.x1) * 0.5, r.h * 0.25, START_Z - r.p1 + 0.4), Vector3(w, r.h * 0.5, 0.8), Vector3.ZERO, dirt)
	for g in gaps:
		var node := _slab(Vector3((g.x0 + g.x1) * 0.5, -4.0, START_Z - (g.p0 + g.p1) * 0.5),
				Vector3(g.x1 - g.x0, 8.1, g.p1 - g.p0), Vector3.ZERO, dirt)
		var pit := _slab(Vector3((g.x0 + g.x1) * 0.5, 0.06, START_Z - (g.p0 + g.p1) * 0.5),
				Vector3(g.x1 - g.x0 - 0.4, 0.05, g.p1 - g.p0 - 0.4), Vector3.ZERO, world._mat(Color(0.02, 0.015, 0.01), 1.0))
		pit.reparent(node)
		g["node"] = node
		node.visible = g.on

func _build_overpass() -> void:
	var conc: Material = world._mat(Color(0.62, 0.6, 0.56), 0.9)
	overpass = Node3D.new()
	add_child(overpass)
	overpass.global_position = Vector3(AVENUE_X, 0, START_Z - 600.0)
	for sx in [-11.0, 11.0]:
		var pil := _slab(overpass.global_position + Vector3(sx, 4.5, 0), Vector3(1.6, 9.0, 1.6), Vector3.ZERO, conc)
		pil.reparent(overpass)
	var deck := _slab(overpass.global_position + Vector3(0, 9.6, 0), Vector3(80.0, 1.4, 13.0), Vector3.ZERO, conc)
	deck.reparent(overpass)
	deck.name = "Deck"

func _build_tower() -> void:
	var glass: StandardMaterial3D = world.tex_mat("Facade003", 14.0, Color(0.8, 1.0, 1.0), 0.6)
	glass.roughness = 0.12
	glass.roughness_texture = null
	var base_z := START_Z - 720.0
	# clear the block where the tower stands
	for b in world.buildings:
		if b.global_position.x > 12.0 and b.global_position.x < 60.0 and absf(b.global_position.z - base_z) < 30.0:
			b.visible = false
	# the tower that falls across the avenue and becomes the drive-through tunnel
	for b in world.buildings:
		if b.global_position.x > -150.0 and b.global_position.x < 60.0 and absf(b.global_position.z - base_z) < 22.0:
			b.visible = false
	tower = FallenTower.new()
	add_child(tower)
	tower.build(self, glass, Vector3(AVENUE_X + 22.0, 0, base_z))
	tower_pivot = tower

func _build_wave() -> void:
	wave = Node3D.new()
	add_child(wave)
	for i in 34:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		var sz := randf_range(26.0, 46.0)
		q.size = Vector2(sz, sz)
		mi.mesh = q
		mi.material_override = smoke_mat
		mi.position = Vector3(randf_range(-70.0, 70.0), randf_range(6.0, 34.0), randf_range(0.0, 30.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wave.add_child(mi)
		wave_puffs.append(mi)
	var parts := CPUParticles3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(12, 12)
	parts.mesh = pq
	parts.material_override = smoke_mat
	parts.amount = 140
	parts.lifetime = 3.5
	parts.local_coords = false
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	parts.emission_box_extents = Vector3(60, 3, 3)
	parts.direction = Vector3(0, 0.4, -1)
	parts.spread = 30.0
	parts.initial_velocity_min = 6.0
	parts.initial_velocity_max = 14.0
	parts.gravity = Vector3(0, 1.5, 0)
	parts.scale_amount_min = 0.8
	parts.scale_amount_max = 2.4
	wave.add_child(parts)

func _build_letterbox() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	for top in [true, false]:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.anchor_left = 0.0
		r.anchor_right = 1.0
		r.anchor_top = 0.0 if top else 0.885
		r.anchor_bottom = 0.115 if top else 1.0
		layer.add_child(r)
		bars.append(r)

func _set_bars(on: bool) -> void:
	for b in bars:
		b.visible = on

# ---------------------------------------------------------------- effects
func _dust_burst(pos: Vector3, radius: float, amount: int) -> void:
	var parts := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(8, 8)
	parts.mesh = q
	parts.material_override = smoke_mat
	parts.one_shot = true
	parts.explosiveness = 0.85
	parts.amount = amount
	parts.lifetime = 4.0
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = radius
	parts.direction = Vector3.UP
	parts.spread = 70.0
	parts.initial_velocity_min = 3.0
	parts.initial_velocity_max = 10.0
	parts.gravity = Vector3(0, -0.6, 0)
	parts.scale_amount_min = 1.0
	parts.scale_amount_max = 3.0
	add_child(parts)
	parts.global_position = pos
	parts.emitting = true
	get_tree().create_timer(6.0).timeout.connect(parts.queue_free)

func _spawn_cracks(p0: float, p1: float, n: int) -> void:
	var dark: Material = world._mat(Color(0.015, 0.012, 0.01), 1.0)
	for i in n:
		var p := randf_range(p0, p1)
		var x := randf_range(-ROAD_HALF + 1.0, ROAD_HALF - 1.0)
		_slab(Vector3(x, 0.09, START_Z - p), Vector3(randf_range(0.15, 0.4), 0.02, randf_range(3.0, 9.0)),
				Vector3(0, randf_range(-1.2, 1.2), 0), dark)
	shake_t = 1.2

func _open_fissure(p0: float, p1: float, x0: float, x1: float) -> void:
	var g := {"p0": p0, "p1": p1, "x0": x0, "x1": x1, "on": true}
	var node := _slab(Vector3((x0 + x1) * 0.5, -4.0, START_Z - (p0 + p1) * 0.5),
			Vector3(0.1, 8.1, p1 - p0), Vector3.ZERO, world._mat(Color(0.03, 0.02, 0.015), 1.0))
	g["node"] = node
	gaps.append(g)
	var tw := create_tween()
	tw.tween_property(node, "scale:x", (x1 - x0) / 0.1, 2.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dust_burst(node.global_position + Vector3(0, 4, 0), 12.0, 50)

func _nearest_building(p: float, side: float) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for b in world.buildings:
		if not b.visible or signf(b.global_position.x - AVENUE_X) != side:
			continue
		var d: float = absf(b.global_position.z - (START_Z - p)) + absf(b.global_position.x - AVENUE_X) * 0.5
		if d < bd:
			bd = d
			best = b
	return best

func _collapse_building_near(p: float, side: float) -> void:
	var b := _nearest_building(p, side)
	if b == null:
		return
	_dust_burst(b.global_position + Vector3(0, 6, 0), 10.0, 60)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "position:y", b.position.y - 22.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(b, "rotation:z", b.rotation.z + side * 0.35, 3.0)

func _tilt_buildings(p0: float, p1: float) -> void:
	var k := 0
	for b in world.buildings:
		var p: float = START_Z - b.global_position.z
		if p < p0 or p > p1 or absf(b.global_position.x - AVENUE_X) > 70.0:
			continue
		var side := signf(b.global_position.x - AVENUE_X)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(b, "rotation:z", b.rotation.z + side * randf_range(0.12, 0.3), 3.5).set_delay(k * 0.15)
		tw.tween_property(b, "position:y", b.position.y - randf_range(2.0, 6.0), 3.5).set_delay(k * 0.15)
		_dust_burst(b.global_position + Vector3(0, 2, 0), 8.0, 20)
		k += 1

func _spawn_oncoming(z: float) -> void:
	var ps := load(CAR_MODELS + "Taxi.fbx") as PackedScene
	if ps == null:
		return
	var holder: Node3D = world._place_fit(ps, Vector3(AVENUE_X + 3.8, 0, z), 4.8, PI, false)
	var body := AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 1.5, 4.8)
	cs.shape = bs
	cs.position.y = 0.75
	body.add_child(cs)
	holder.add_child(body)
	movers.append({"node": holder, "vel": Vector3(0, 0, 21.0), "life": 9.0, "spin": Vector3.ZERO, "swerve": true})

func _drop_tower() -> void:
	world._msg("LOOK UP!", 2.0)
	shake_t = 2.5
	_dust_burst(tower.global_position + Vector3(10, 10, 0), 16.0, 80)
	tower.fall(3.0)

func _facade_rain() -> void:
	var glass_mat: Material = world._mat(Color(0.55, 0.75, 0.78), 0.1)
	var zc := START_Z - 770.0
	for i in 26:
		var shard := _slab(Vector3(AVENUE_X + randf_range(-10.0, 10.0), randf_range(30.0, 70.0), zc + randf_range(-25.0, 25.0)),
				Vector3(randf_range(1.0, 3.0), 0.08, randf_range(1.0, 3.0)), Vector3(randf(), randf(), randf()), glass_mat)
		movers.append({"node": shard, "vel": Vector3(randf_range(-2, 2), -randf_range(8, 16), 0), "life": 6.0,
				"spin": Vector3(randf_range(-4, 4), randf_range(-4, 4), 0), "ground": true})
	# two big facade panels block the left lanes: keep right
	var conc: Material = world._mat(Color(0.35, 0.42, 0.44), 0.4)
	for k in 2:
		var slab := _slab(Vector3(AVENUE_X - 4.0, 22.0 + k * 6.0, zc - 10.0 - k * 22.0), Vector3(8.0, 1.2, 6.0), Vector3(0.3, 0, 0.2), conc)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(8.0, 1.2, 6.0)
		cs.shape = bs
		sb.add_child(cs)
		slab.add_child(sb)
		movers.append({"node": slab, "vel": Vector3(0, -18.0, 0), "life": 30.0, "spin": Vector3.ZERO, "ground": true, "land_y": 0.6})
	# a parked car gets flipped past the limo
	var flip := _nearest_curb_prop(START_Z - 775.0)
	if flip:
		movers.append({"node": flip, "vel": Vector3(-6.0, 11.0, 4.0), "life": 4.0, "spin": Vector3(5.0, 0, 3.0), "ballistic": true})

func _nearest_curb_prop(z: float) -> Node3D:
	var best: Node3D = null
	var bd := 40.0
	for c in get_parent().get_children():
		if c is Node3D and c.has_meta("fit") and absf(c.global_position.x - AVENUE_X) < 8.0:
			var d: float = absf(c.global_position.z - z)
			if d < bd:
				bd = d
				best = c
	return best

func _update_movers(delta: float) -> void:
	for i in range(movers.size() - 1, -1, -1):
		var m: Dictionary = movers[i]
		var n: Node3D = m.node
		if not is_instance_valid(n):
			movers.remove_at(i)
			continue
		m.life -= delta
		if m.get("ballistic", false):
			m.vel.y -= 26.0 * delta
		if m.get("swerve", false):
			n.position.x += sin(m.life * 2.5) * 3.0 * delta
		n.global_position += m.vel * delta
		n.rotation += m.spin * delta
		if m.get("ground", false) and n.global_position.y <= m.get("land_y", 0.1):
			n.global_position.y = m.get("land_y", 0.1)
			m.vel = Vector3.ZERO
			m.spin = Vector3.ZERO
		if m.life <= 0.0:
			if m.get("land_y", -1.0) < 0.0:
				n.queue_free()
			movers.remove_at(i)
	# the overpass drops right after the limo clears it
	if overpass and overpass.has_node("Deck") and progress() > 607.0 and not overpass.has_meta("down"):
		overpass.set_meta("down", true)
		var deck := overpass.get_node("Deck") as Node3D
		var tw := create_tween().set_parallel(true)
		tw.tween_property(deck, "position:y", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(deck, "rotation:x", 0.25, 1.1)
		_dust_burst(deck.global_position - Vector3(0, 6, 0), 14.0, 70)
		shake_t = 1.8


# ---------------------------------------------------------------- people
func _spawn_crowd(p_center: float, n: int) -> void:
	if people.is_empty():
		return
	for i in n:
		var ps: PackedScene = people[randi() % people.size()]
		var holder := Node3D.new()
		add_child(holder)
		var model := ps.instantiate()
		holder.add_child(model)
		var bb := CityCar.model_aabb(holder)
		var s := 1.75 / maxf(bb.size.y, 0.01)
		holder.scale = Vector3(s, s, s)
		var side := -1.0 if randf() < 0.5 else 1.0
		var crossing := randf() < 0.25
		var pos := Vector3(AVENUE_X + side * randf_range(10.0, 15.0), 0, START_Z - p_center - randf_range(-30.0, 30.0))
		var vel := Vector3(0, 0, -randf_range(4.5, 7.5))   # fleeing the same way as the limo
		if crossing:
			pos.x = AVENUE_X + side * 12.0
			vel = Vector3(-side * randf_range(4.0, 6.0), 0, -1.0)
		holder.global_position = pos
		holder.look_at(pos + vel.normalized(), Vector3.UP, true)
		var ap := _find_anim(model)
		if ap:
			var pick := ""
			for a in ap.get_animation_list():
				if a.to_lower().contains("run"):
					pick = a
					break
			if pick == "" and ap.get_animation_list().size() > 0:
				pick = ap.get_animation_list()[0]
			if pick != "":
				var anim := ap.get_animation(pick)
				anim.loop_mode = Animation.LOOP_LINEAR
				ap.play(pick)
				ap.seek(randf() * anim.length)
		runners.append({"node": holder, "vel": vel, "life": 14.0})

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null

func _update_runners(delta: float) -> void:
	var car: CityCar = world.car
	for i in range(runners.size() - 1, -1, -1):
		var r: Dictionary = runners[i]
		var n: Node3D = r.node
		r.life -= delta
		# dodge the limo
		var d := n.global_position - car.global_position
		d.y = 0
		if d.length() < 7.0:
			var away := Vector3(signf(d.x) if d.x != 0.0 else 1.0, 0, 0) * 9.0
			r.vel = r.vel.lerp(away, 0.3)
			n.look_at(n.global_position + r.vel.normalized(), Vector3.UP, true)
		n.global_position += r.vel * delta
		if r.life <= 0.0 or world.ground_height_at(n.global_position.x, n.global_position.z) < -5.0:
			n.queue_free()
			runners.remove_at(i)


# ---------------------------------------------------------------- downtown (film 3:35-4:55: Wilshire mid-rises)
func _build_downtown() -> void:
	var sets := [["Facade005", 18.0], ["Facade001", 20.0], ["Facade002", 20.0], ["Facade003", 16.0]]
	var mats: Array[StandardMaterial3D] = []
	for st in sets:
		mats.append(world.tex_mat(st[0], st[1]))
	var roof: Material = world._mat(Color(0.35, 0.33, 0.3), 0.9)
	for b in world.buildings:
		var p: float = START_Z - b.global_position.z
		if p > 320.0 and absf(b.global_position.x - AVENUE_X) < 75.0:
			b.visible = false
	for side in [-1.0, 1.0]:
		var p := 330.0
		while p < 960.0:
			var w := randf_range(22.0, 32.0)
			var d := randf_range(22.0, 30.0)
			var h := randf_range(28.0, 95.0)
			var near_tower: bool = absf(p - 720.0) < 26.0
			var crossing := fmod(p + 20.0, 100.0) < 22.0   # keep side streets open
			if not near_tower and not crossing:
				var x: float = AVENUE_X + side * (19.0 + w * 0.5)
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(w, h, d)
				mi.mesh = bm
				mi.material_override = mats[randi() % mats.size()]
				var holder := Node3D.new()
				world.add_child(holder)
				holder.global_position = Vector3(x, 0, START_Z - p)
				holder.add_child(mi)
				mi.position.y = h * 0.5
				var cap := MeshInstance3D.new()
				var cm := BoxMesh.new()
				cm.size = Vector3(w + 0.6, 1.2, d + 0.6)
				cap.mesh = cm
				cap.material_override = roof
				cap.position.y = h + 0.6
				holder.add_child(cap)
				var sb := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = bm.size
				cs.shape = bs
				cs.position.y = h * 0.5
				sb.add_child(cs)
				holder.add_child(sb)
				world.buildings.append(holder)
			p += d + randf_range(2.0, 6.0)
