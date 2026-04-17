class_name PlayerSpawner
extends Node

var _characters: Array[CombatCharacter] = []

func _ready() -> void:
	for slot in get_children():
		var character: CombatCharacter = slot.get_child(0)
		_characters.append(character)
	Log.info("PlayerSpawner ready, slots:", _characters.size())

func initialize() -> void:
	for i in _characters.size():
		var character = _characters[i]
		var slot_data = PartyManager.get_slot(i)
		if slot_data.is_empty(): 
			continue
		else:
			character.initialize_player(slot_data["player_data"], slot_data["save_data"])

func reset_characters() -> void:
	for character in _characters:
		character.reset_for_combat()
