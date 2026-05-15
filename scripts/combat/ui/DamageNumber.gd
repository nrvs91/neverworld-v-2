class_name DamageNumber
extends Node3D

const TWEEN_DURATION: float = 0.8
const FLOAT_DISTANCE: float = 0.6

@onready var number_label: Label3D = $NumberLabel

func show_at(world_pos: Vector3, amount: int) -> void:
	_show(world_pos, str(amount))

func show_text_at(world_pos: Vector3, text: String) -> void:
	_show(world_pos, text)

func _show(world_pos: Vector3, text: String) -> void:
	global_position = world_pos
	number_label.text = text
	var end_y: float = position.y + FLOAT_DISTANCE
	var tween := create_tween()
	tween.tween_property(self, "position:y", end_y, TWEEN_DURATION)
	tween.parallel().tween_property(number_label, "modulate:a", 0.0, TWEEN_DURATION)
	tween.tween_callback(_on_tween_done)

func _on_tween_done() -> void:
	queue_free()
