extends CharacterBody3D
class_name CityCar

signal damaged(health: int)
signal wrecked
signal impact(strength: float)

const MAX_SPEED := 44.0
const REVERSE_SPEED := 14.0
const ACCEL := 15.0
const BRAKE := 34.0
const ROLL_DRAG := 2.8
const TURN_RATE := 1.8
const GRAVITY := 26.0
const START_HEALTH := 3

var world: Node = null
var speed := 0.0
var heading := 0.0
var steer_input := 0.0
var throttle := 0.0
var health := START_HEALTH
var falling := false
var fall_vel := 0.0
var dead := false
var frozen := true
var body_offset := 0.0
var engine_load := 0.0
var screeching := false
var last_speed := 0.0
var hit_cool := 0.0
var ground := 0.0
var car_size := Vector3(2.2, 1.5, 6.6)
var collider: CollisionShape3D

static func model_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var has := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
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

static func fit_model(holder: Node3D, packed: PackedScene, target_len: float) -> Vector3:
	var model := packed.instantiate()
	holder.add_child(model)
	var size := model_aabb(holder).size
	if size.x > size.z:
		holder.rotation_degrees.y = 90.0
	var s := target_len / maxf(maxf(size.x, size.z), 0.001)
	holder.scale = Vector3(s, s, s)
	var bb := model_aabb(holder)
	var c := bb.get_center()
	holder.position -= Vector3(c.x, bb.position.y, c.z)
	return bb.size

func attach_model(packed: PackedScene, target_len: float) -> Vector3:
	var holder := Node3D.new()
	holder.name = "Body"
	add_child(holder)
	var size := fit_model(holder, packed, target_len)
	car_size = Vector3(maxf(size.x, 1.2), maxf(size.y, 0.8), maxf(size.z, 3.0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(car_size.x * 0.9, car_size.y, car_size.z * 0.96)
	collider = CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, shape.size.y * 0.5, 0)
	add_child(collider)
	collision_layer = 2
	collision_mask = 1
	return car_size

func _physics_process(delta: float) -> void:
	if hit_cool > 0.0:
		hit_cool -= delta
	if falling:
		fall_vel -= GRAVITY * delta
		global_position.y += fall_vel * delta
		rotation.x += 1.1 * delta
		rotation.z = sin(float(Time.get_ticks_msec()) * 0.004) * 0.3
		velocity = Vector3.ZERO
		return
	if dead:
		speed = move_toward(speed, 0.0, BRAKE * delta)
		velocity = Vector3.ZERO
		engine_load = 0.0
		screeching = false
		return

	var up := 0.0
	var down := 0.0
	var steer := 0.0
	var handbrake := false
	if not frozen:
		if Input.is_action_pressed("accel") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			up = 1.0
		if Input.is_action_pressed("reverse") or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			down = 1.0
		if Input.is_action_pressed("steer_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			steer -= 1.0
		if Input.is_action_pressed("steer_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			steer += 1.0
		handbrake = Input.is_action_pressed("handbrake") or Input.is_key_pressed(KEY_SHIFT)

	throttle = up - down
	if up > 0.0:
		speed = move_toward(speed, MAX_SPEED, ACCEL * delta)
	elif down > 0.0:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, BRAKE * delta)
		else:
			speed = move_toward(speed, -REVERSE_SPEED, ACCEL * delta)
	else:
		speed = move_toward(speed, 0.0, ROLL_DRAG * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, BRAKE * 1.5 * delta)

	steer_input = lerpf(steer_input, steer, 1.0 - exp(-9.0 * delta))
	var speed_factor := clampf(absf(speed) / 14.0, 0.0, 1.0)
	var dir_sign := 1.0 if speed >= 0.0 else -1.0
	heading -= steer_input * TURN_RATE * speed_factor * dir_sign * delta
	rotation.y = heading

	screeching = absf(steer_input) > 0.5 and absf(speed) > 15.0
	engine_load = clampf(absf(speed) / MAX_SPEED, 0.0, 1.0)

	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	ground = 0.0
	if world != null and world.has_method("ground_height_at"):
		ground = world.ground_height_at(global_position.x, global_position.z)
	if ground < -5.0:
		plunge()
		return
	var target_y := ground + body_offset
	if global_position.y < target_y - 0.02:
		global_position.y = minf(target_y, global_position.y + 11.0 * delta)
	elif global_position.y > target_y + 0.02:
		global_position.y = maxf(target_y, global_position.y - 18.0 * delta)
	velocity.y = 0.0

	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	last_speed = speed
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other == null:
			continue
		if absf(last_speed) > 4.0 and other.has_method("knock_from_car"):
			var away := forward
			other.call("knock_from_car", away, last_speed)
			impact.emit(clampf(absf(last_speed) / MAX_SPEED, 0.25, 1.0))
			speed *= 0.6
			last_speed = speed
			continue
		if absf(last_speed) > 13.0 and col.get_normal().dot(forward) < -0.35 and hit_cool <= 0.0:
			hit_cool = 1.4
			impact.emit(clampf(absf(last_speed) / MAX_SPEED, 0.35, 1.0))
			take_hit(1)
			speed *= 0.3
			last_speed = speed

func take_hit(amount: int) -> void:
	if dead:
		return
	health = maxi(0, health - amount)
	damaged.emit(health)
	if health <= 0:
		dead = true
		wrecked.emit()

func plunge() -> void:
	if falling:
		return
	falling = true
	fall_vel = -3.0
	speed = 0.0

func reset_car(pos: Vector3, yaw: float) -> void:
	dead = false
	falling = false
	frozen = false
	speed = 0.0
	fall_vel = 0.0
	health = START_HEALTH
	steer_input = 0.0
	hit_cool = 0.0
	last_speed = 0.0
	heading = yaw
	rotation = Vector3(0, yaw, 0)
	global_position = pos
	velocity = Vector3.ZERO
	damaged.emit(health)

func forward_vector() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))

func speed_kmh() -> float:
	return absf(speed) * 3.6
