class_name ExplorationEnvironment
extends Node

@export var scene: PackedScene
var _instance: Node3D = null

func enter() -> void:
	if scene == null:
		Log.warn("ExplorationEnvironment: no scene assigned")
		return
	if _instance:
		_instance.queue_free()
	_instance = scene.instantiate()
	add_child(_instance)
	Log.info("ExplorationEnvironment: geometry loaded")

func exit() -> void:
	if _instance:
		_instance.queue_free()
		_instance = null
	Log.info("ExplorationEnvironment: geometry cleared")

func hide_geometry() -> void:
	if _instance:
		_instance.visible = false

func show_geometry() -> void:
	if _instance:
		_instance.visible = true
