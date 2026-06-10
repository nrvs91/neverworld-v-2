class_name QuickPlayerController
extends CharacterBody3D

@export var speed: float = 6.0

var _camera_rig: Node3D


func _ready() -> void:
	_camera_rig = get_node("../CameraRig")


func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector(
		&"movement_left", &"movement_right", &"movement_up", &"movement_down"
	)

	var forward := _camera_rig.global_transform.basis.z
	forward.y = 0.0
	forward = -forward.normalized()

	var right := _camera_rig.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var direction := forward * input_dir.y + right * input_dir.x

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		velocity = Vector3(direction.x * speed, velocity.y, direction.z * speed)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

	_camera_rig.global_position = global_position
