class_name ZoneExit extends Area3D

@export_file("*.tscn") var target_zone_path: String
@export var target_spawn_point: StringName = &"default"

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	Log.debug("ready")

func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player"):
		return
	if target_zone_path.is_empty():
		Log.warn("no target zone path set")
		return
	var zone := load(target_zone_path) as PackedScene
	Log.info("zone exit triggered, target:", target_zone_path)
	ExplorationEvents.zone_exit_requested.emit(zone, target_spawn_point)

func _exit_tree() -> void:
	if area_entered.is_connected(_on_area_entered):
		area_entered.disconnect(_on_area_entered)
