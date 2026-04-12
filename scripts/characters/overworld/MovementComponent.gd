# MovementComponent - Character Movement Physics
#
# Applies movement to the parent node based on input signals.
# Isometric projection handled via 45-degree rotation of input.
#
# LOGGING NOTES:
#   - Log.info in _ready (component lifecycle)
#   - Avoid logging in _physics_process (called every frame)
#   - Log direction changes at the signal handler level instead

class_name MovementComponent
extends Node3D

@export var controller: Node
@export var movement_speed := 1.0
@export var step_distance: float = 1.0

var _distance_accumulated: float = 0.0
var _direction := Vector2.ZERO
var _is_running := false

func _ready() -> void:
	Log.info("Initializing...")
	controller.direction_changed.connect(_on_direction_changed)
	controller.run_toggled.connect(_on_run_toggled)

func _physics_process(delta: float) -> void:
	if _direction == Vector2.ZERO:
		return
	var rotated := _direction.rotated(PI / 4)
	var speed := movement_speed * (1.8 if _is_running else 1.0)
	var move := Vector3(rotated.x, 0.0, rotated.y).normalized()
	get_parent().position += move * speed * delta
	var move_amount := (move * speed* delta).length()
	_distance_accumulated += move_amount
	if _distance_accumulated >= step_distance:
		_distance_accumulated -= step_distance
		ExplorationEvents.step_taken.emit()

func _on_direction_changed(dir: Vector2) -> void:
	_direction = dir

func _on_run_toggled(running: bool) -> void:
	_is_running = running
