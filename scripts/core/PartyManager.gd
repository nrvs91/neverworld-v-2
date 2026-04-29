extends Node

var save_data: GlobalSaveData = null

# Registry of all known PlayerData resources, keyed by character_ID.
# TODO: replace with folder scan once more PlayerData .tres files exist.
var _registry: Dictionary = {}

func _ready() -> void:
	Log.info("ready")
	_load_registry()
	#_load_save()

func _load_registry() -> void:
	# Hardcoded for now — add an entry here each time you create a PlayerData .tres.
	# Example once Skugge's .tres exists:
	# _registry["skugge"] = preload("res://data/characters/skugge.tres")
	pass

func _load_save() -> void:
	# TODO: load from disk. For now, always start a new game.
	start_new_game()

func start_new_game() -> void:
	save_data = GlobalSaveData.new()
	# Skugge is always the starting character.
	# Add her PlayerData .tres to _registry first, then uncomment:
	# recruit("skugge")
	# save_data.party_slots[0] = "skugge"
	Log.info("new game started")

# Adds a character to the roster using their PlayerData as the starting template.
# Safe to call multiple times — will not overwrite existing save data.
func recruit(char_id: String) -> void:
	if save_data.roster.has(char_id):
		Log.warn("recruit skipped, already in roster", char_id)
		return
	var player_data: PlayerData = _registry.get(char_id, null)
	if player_data == null:
		Log.error("recruit failed, no player data for", char_id)
		return
	var char_save := CharacterSaveData.new()
	char_save.character_level = player_data.starting_level
	char_save.cur_hp = player_data.MaxHP
	char_save.cur_mp = player_data.MaxMP
	save_data.roster[char_id] = char_save
	Log.info("character recruited", char_id, char_save.character_level)

# Assigns a roster character to an active party slot (0, 1, or 2).
func assign_slot(slot: int, char_id: String) -> void:
	if not save_data.roster.has(char_id):
		Log.error("assign slot failed, not in roster", char_id)
		return
	save_data.party_slots[slot] = char_id
	Log.info("party slot assigned", slot, char_id)

# Returns {player_data: PlayerData, save_data: CharacterSaveData} for the given slot,
# or an empty Dictionary if the slot is empty or unregistered.
func get_slot(index: int) -> Dictionary:
	if index >= save_data.party_slots.size():
		return {}
	var char_id: String = save_data.party_slots[index]
	if char_id.is_empty():
		return {}
	var player_data: PlayerData = _registry.get(char_id, null)
	var char_save: CharacterSaveData = save_data.roster.get(char_id, null)
	if player_data == null or char_save == null:
		return {}
	return { "player_data": player_data, "save_data": char_save }
