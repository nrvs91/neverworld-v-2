class_name PlayerInputComponent
extends Node

signal direction_changed(direction: Vector2)
signal run_toggled(running: bool)
signal interact_pressed

func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.y = Input.get_axis("ui_up", "ui_down")
	direction_changed.emit(direction)
	
	var running := Input.is_action_pressed("ui_accept")
	run_toggled.emit(running)
	
	if Input.is_action_just_pressed("interact"):
		interact_pressed.emit()
