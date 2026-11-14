extends Node3D
class_name FallenTower
# Film 4:18-4:44: the glass office tower topples across the avenue and the limo drives
# straight through one of its floors - in through the curtain wall, past sideways desks,
# flickering lights and flying papers, and out through the glass on the other side.
#
# Built standing in local space (pivot = base edge nearest the road, tower grows +Y and +X),
# then rotated +90 deg about Z so it lies across the road: local +Y -> world -X, local X -> world Y.

const W := 22.0          # footprint (becomes the tunnel height and depth)
const H := 150.0         # height (becomes the length lying across the street)
const FLOOR := 7.0       # floor-to-floor; after the fall these slabs are the tunnel walls
const FIRST := 4.5       # first slab, chosen so the avenue centre falls between two slabs

var director
var landed := false
var falling := false
var entry_pane: MeshInstance3D
var exit_pane: MeshInstance3D
var entry_broken := false
var exit_broken := false
var bodies: Array[CollisionShape3D] = []
var lights: Array[OmniLight3D] = []
var papers: CPUParticles3D
var t := 0.0

func build(dir, glass: Material, base_world: Vector3) -> void:
	director = dir
	global_position = base_world
	var conc: Material = dir.world._mat(Color(0.42, 0.41, 0.39), 0.95)
	var dark: Material = dir.world._mat(Color(0.12, 0.12, 0.13), 0.9)
	var desk_m: Material = dir.world._mat(Color(0.5, 0.42, 0.32), 0.7)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.85, 0.95, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.8, 0.92, 1.0)
	glow.emission_energy_multiplier = 3.0
	# shell: roof side (local x = W) and the two big facades (local z = +-W/2)
	_box(Vector3(W - 0.2, H * 0.5, 0), Vector3(0.4, H, W), glass)
	# facades are split so the pane in front of the drive-through floor can shatter
	var lane_lo := _lane_lo()
	var lane_hi := lane_lo + FLOOR
	for zf in [W * 0.5, -W * 0.5]:
		_box(Vector3(W * 0.5, lane_lo * 0.5, zf), Vector3(W, lane_lo, 0.3), glass)
		_box(Vector3(W * 0.5, (lane_hi + H) * 0.5, zf), Vector3(W, H - lane_hi, 0.3), glass)
		var pane := _box(Vector3(W * 0.5, (lane_lo + lane_hi) * 0.5, zf), Vector3(W, FLOOR, 0.3), glass)
		if zf > 0.0:
			entry_pane = pane
		else:
			exit_pane = pane
	# floor slabs (tunnel walls once fallen), with collision so the lobby is the only way through
	var y := FIRST
	while y < H - 2.0:
		var slab := _box(Vector3(W * 0.5, y, 0), Vector3(W, 0.45, W - 0.4), conc)
		_collider(slab, Vector3(W, 0.45, W - 0.4))
		y += FLOOR
	# the drive-through floor: desks bolted to its floor (now a wall), lights on its ceiling
	for i in 7:
		var dz := -8.0 + i * 2.7
		for dx in [3.0, 9.0, 15.0]:
			_box(Vector3(dx + randf_range(-1, 1), lane_lo + 0.55, dz), Vector3(1.6, 0.9, 0.9), desk_m)
			_box(Vector3(dx + 0.6, lane_lo + 1.1, dz), Vector3(0.1, 0.5, 0.7), dark)   # monitor
	for i in 5:
		var lz := -8.0 + i * 4.0
		for lx in [4.0, 11.0, 18.0]:
			_box(Vector3(lx, lane_hi - 0.3, lz), Vector3(3.0, 0.08, 0.6), glow)
	# a few broken columns hanging across the corridor (slightly tilted, film 4:31)
	for i in 4:
		var c := _box(Vector3(randf_range(14.0, 20.0), (lane_lo + lane_hi) * 0.5, -8.0 + i * 5.0),
				Vector3(0.8, FLOOR, 0.8), conc)
		c.rotation.z = randf_range(-0.25, 0.25)
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(0.75, 0.9, 1.0)
		l.omni_range = 9.0
		l.light_energy = 2.0
		l.position = Vector3(6.0 + (i % 2) * 8.0, (lane_lo + lane_hi) * 0.5, -7.0 + i * 5.0)
		l.visible = false
		add_child(l)
		lights.append(l)
	papers = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.4)
	papers.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.95, 0.95, 0.92)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	papers.material_override = pm
	papers.amount = 220
	papers.lifetime = 3.0
	papers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	papers.emission_box_extents = Vector3(W * 0.45, FLOOR * 0.45, W * 0.45)
	papers.position = Vector3(W * 0.5, (lane_lo + lane_hi) * 0.5, 0)
	papers.gravity = Vector3(0, -1.0, 0)
	papers.initial_velocity_min = 2.0
	papers.initial_velocity_max = 6.0
	papers.spread = 180.0
	papers.angular_velocity_min = -300.0
	papers.angular_velocity_max = 300.0
	papers.emitting = false
	add_child(papers)

func _lane_lo() -> float:
	# slab whose world X (= base.x - local y) sits just right of the avenue centre
	var target: float = global_position.x - (ChaseDirector.AVENUE_X + FLOOR * 0.5)
	var k := floori((target - FIRST) / FLOOR)
	return FIRST + k * FLOOR

func _box(pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi

func _collider(on: Node3D, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.disabled = true      # only solid once the tower is down
	sb.add_child(cs)
	on.add_child(sb)
	bodies.append(cs)

func fall(seconds: float) -> void:
	if falling:
		return
	falling = true
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", PI * 0.5, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_on_land)

func _on_land() -> void:
	landed = true
	for cs in bodies:
		cs.disabled = false
	for l in lights:
		l.visible = true
	director.shake_t = 2.5
	var x := global_position.x
	while x > global_position.x - H:
		if absf(x - ChaseDirector.AVENUE_X) > 14.0:   # keep the lobby itself readable
			director._dust_burst(Vector3(x, 6.0, global_position.z), 12.0, 25)
		x -= 22.0
	director.world._msg("DRIVE THROUGH THE LOBBY!", 2.0)

func update(delta: float, car_pos: Vector3) -> void:
	t += delta
	if not landed:
		return
	var dz := car_pos.z - global_position.z
	if not entry_broken and dz < W * 0.5 + 14.0 and dz > -W:
		entry_broken = true
		_shatter(entry_pane)
	if not exit_broken and dz < -W * 0.5 + 10.0:
		exit_broken = true
		_shatter(exit_pane)
	var inside := absf(dz) < W * 0.5 + 4.0
	papers.emitting = inside
	for i in lights.size():
		lights[i].light_energy = 0.0 if sin(t * (13.0 + i * 7.0)) > 0.55 else 2.2
	if inside and randf() < delta * 6.0:
		# ceiling debris shaking loose inside the floor
		var chunk := _box(Vector3(randf_range(2.0, 20.0), _lane_lo() + FLOOR - 0.6, randf_range(-9.0, 9.0)),
				Vector3(randf_range(0.3, 1.2), 0.3, randf_range(0.3, 1.2)), director.world._mat(Color(0.5, 0.5, 0.48)))
		director.movers.append({"node": chunk, "vel": Vector3(randf_range(-2.0, 2.0), -9.0, 0), "life": 2.2, "spin": Vector3(3, 2, 1)})

func _shatter(pane: MeshInstance3D) -> void:
	if pane == null:
		return
	var at := pane.global_position
	pane.visible = false
	var gm: Material = director.world._mat(Color(0.6, 0.8, 0.82), 0.1)
	for i in 30:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.2, 0.9), 0.03, randf_range(0.2, 0.9))
		s.mesh = bm
		s.material_override = gm
		director.add_child(s)
		s.global_position = at + Vector3(randf_range(-5, 5), randf_range(-3, 5), 0)
		director.movers.append({"node": s, "vel": Vector3(randf_range(-4, 4), randf_range(-2, 5), randf_range(-14, -4)),
				"life": 3.0, "spin": Vector3(randf_range(-8, 8), randf_range(-8, 8), 0), "ballistic": true})
	director.shake_t = maxf(director.shake_t, 0.8)
