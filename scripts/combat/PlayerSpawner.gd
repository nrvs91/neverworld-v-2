class_name PlayerSpawner
extends Node

const CombatCharacterScene = preload("res://scenes/combat/combat_character.tscn")                                                                 

func initialize() -> void:
	clear()
	var slots = get_children()
	for i in slots.size():
		var slot = slots[i]
		var slot_data = PartyManager.get_slot(i)
		if slot_data.is_empty():
			continue
		var character = CombatCharacterScene.instantiate()
		slot.add_child(character)
		character.initialize_player(slot_data["player_data"], slot_data["save_data"])
	Log.info("ready")

func clear() -> void:
	for slot in get_children():
		for child in slot.get_children():
			child.queue_free()
	Log.info("cleared")

func get_character(slot_index: int) -> CombatCharacter:
	if slot_index >= get_child_count():
		return null
	var character = get_child(slot_index).get_child(0)
	return character as CombatCharacter
