# PlayerInputComponent - Input Processing for Player Characters
#
# Reads input actions and emits signals for movement and interaction.
# Implements input buffering - only emits when state changes.
#
# LOGGING NOTES:
#   - Log.info in _ready (component lifecycle)
#   - Log.debug on direction changes (input state)
#   - Avoid logging every frame - use change detection

class_name PlayerInputComponent
extends Node

signal direction_changed(direction: Vector2)
signal run_toggled(running: bool)
signal interact_pressed

var _last_direction := Vector2.ZERO
var _last_running := false

func _ready() -> void:
	Log.info("Initializing...")

func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("movement_left", "movement_right")
	direction.y = Input.get_axis("movement_up", "movement_down")

	if direction != _last_direction:
		#Log.debug("Input direction: ", direction)
		_last_direction = direction
		direction_changed.emit(direction)
	
	var running := Input.is_action_pressed("movement_run")
	if running != _last_running:
		_last_running = running
		run_toggled.emit(running)
	
	if Input.is_action_just_pressed("interact"):
		interact_pressed.emit()
