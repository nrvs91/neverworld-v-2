class_name StatsComponent
extends Node

var _stats: Dictionary = {}

func setup(stats: Dictionary) -> void:
	_stats = stats.duplicate()
	Log.info("StatsComponent setup")

func stat(key: CharacterStats.Stat) -> int:
	return _stats.get(key, 0)
