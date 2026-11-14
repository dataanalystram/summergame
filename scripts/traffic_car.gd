extends AnimatableBody3D
class_name TrafficCar

var world: Node = null
var axis := 0
var dir := 1.0
var speed := 13.0
var lane_pos := 0.0
var falling := false
var fall_vel := 0.0
var spin := 0.0
var model_holder: Node3D


func setup(forward_axis: int, direction: float, lane: float, travel_speed: float) -> void:
	axis = forward_axis
	dir = direction
	lane_pos = lane
	speed = travel_speed
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.4, 4.4)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.7, 0)
	add_child(cs)
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true


func _physics_process(delta: float) -> void:
	if falling:
		fall_vel -= 26.0 * delta
		position.y += fall_vel * delta
		rotation.x += 1.0 * delta
		rotation.z += spin * delta
		return
	var fwd := (dir * speed * delta)
	if axis == 0:
		position.z += fwd
		rotation.y = 0.0 if dir > 0.0 else PI
		if position.z > 460.0:
			position.z = -460.0
		elif position.z < -460.0:
			position.z = 460.0
	else:
		position.x += fwd
		rotation.y = -PI * 0.5 if dir > 0.0 else PI * 0.5
		if position.x > 460.0:
			position.x = -460.0
		elif position.x < -460.0:
			position.x = 460.0
	if world != null and world.has_method("tile_is_gone_at"):
		if world.tile_is_gone_at(position.x, position.z):
			falling = true
			fall_vel = -1.0
			spin = randf_range(-1.5, 1.5)
