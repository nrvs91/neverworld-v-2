class_name ZoneExit extends Area3D

@export var target_zone: PackedScene
@export var target_spawn_point: StringName = &"default"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	Log.info("ready")

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if target_zone == null:
		Log.warn("no target zone set")
		return
	Log.info("zone exit triggered, target:", target_zone.resource_path) 
	ExplorationEvents.zone_exit_requested.emit(target_zone, target_spawn_point)

func _exit_tree() -> void:
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)
