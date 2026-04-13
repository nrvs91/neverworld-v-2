class_name StepCounter
extends Node

signal threshold_reached

const RESET_VALUE: int = 256

var _counter: int = RESET_VALUE

func _ready() -> void:
	Log.info("StepCounter ready, counter =", _counter)
	ExplorationEvents.step_taken.connect(_on_step_taken)

func _exit_tree() -> void:
	ExplorationEvents.step_taken.disconnect(_on_step_taken)

func _on_step_taken(_who: Node3D) -> void:
	_counter -= randi_range(1, 8)
	Log.debug("step_counter", "remaining", _counter)
	if _counter <= 0:
		_counter = RESET_VALUE
		Log.info("StepCounter threshold reached, resetting to", RESET_VALUE)
		threshold_reached.emit()
