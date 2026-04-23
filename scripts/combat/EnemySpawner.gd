class_name EnemySpawner
extends Node

const CombatCharacterScene = preload ("res://scenes/combat/combat_character.tscn")

func clear() -> void:
	for slot in get_children():
		for child in slot.get_children():
			child.queue_free()
	Log.info("EnemySpawner cleared")

func initialize(composition: CombatConfig):
	clear()
	var slots := get_children()
	for i in composition.slots.size():
		var enemy_data = composition.slots[i]
		if enemy_data == null:
			continue
		var character = CombatCharacterScene.instantiate()
		slots[i].add_child(character)
		character.initialize_enemy(enemy_data)
	Log.info("EnemySpawner initialized.")
