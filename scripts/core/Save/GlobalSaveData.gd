class_name GlobalSaveData
extends Resource

# active party, 3 slots for 3 active player characters
# ordered by index, empty slow = "", always exactly 3 entries, even if some are empty
@export var party_slots: Array[String] = ["","",""]

# every character met - active party member or bench
# keyed by character_ID, a character is added via PartyManager.recruit()
# their save data persists here forever after
@export var roster: Dictionary [String, CharacterSaveData] = {}