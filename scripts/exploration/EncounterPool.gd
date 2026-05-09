class_name EncounterPool
extends Node

@export var entries: Array[EncounterPoolEntry] = []

func pick() -> CombatConfig:
	if entries.is_empty():
		Log.warn("pick called on empty pool")
		return null

	var total_weight: int = 0
	for entry in entries:
		total_weight += entry.weight
	
	var roll: int = randi() % total_weight
	for entry in entries:
		roll -= entry.weight
		if roll < 0:
			Log.debug("encounter picked", entry.composition.resource_path)
			return entry.composition
	#fallback
	return entries[-1].composition
