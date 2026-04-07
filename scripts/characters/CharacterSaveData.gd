class_name CharacterSaveData
extends Resource

@export var cur_hp: int = 1
@export var cur_mp: int = 1
@export var character_level: int = 1
@export var cur_xp: int

@export var equipped_weapon_id: String
@export var equipped_armor_id: String
@export var equipped_gear_ids: Array[String]
@export var equipped_mnemonic_ids: Array[String]

@export var choice_bonuses: Dictionary[CharacterStats.Stat, int] = {}
@export var stat_last_chosen_level: Dictionary[CharacterStats.Stat, int] = {}