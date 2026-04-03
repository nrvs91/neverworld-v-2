class_name MovementComponent
extends Node3D

@export var controller: Node
@export var MovementSpeed := 200
var _direction := Vector2.ZERO

func _ready() -> void:
	controller.direction_changed.connect(_on_direction_changed)

func _on_direction_changed(dir: Vector2) -> void:
	_direction = dir
