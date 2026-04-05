class_name MovementComponent
extends Node3D

@export var controller: Node
@export var movement_speed := 1.0
var _direction := Vector2.ZERO

func _ready() -> void:
	Log.info("Initializing...")
	controller.direction_changed.connect(_on_direction_changed)

func _physics_process(delta: float) -> void:
	if _direction == Vector2.ZERO:
		return
	var move := Vector3(_direction.x, 0.0, _direction.y).normalized()
	get_parent().position += move * movement_speed * delta

func _on_direction_changed(dir: Vector2) -> void:
	_direction = dir
