class_name CombatCharacter
extends Node3D

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visuals: CombatVisuals = $CombatVisuals
@onready var sfx: CombatSFXComponent = $CombatSFXComponent

func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
	visuals.setup(data.character_sprite)
	vitals.setup(save_data.cur_hp, save_data.cur_mp)
	Log.info("character ready", data.character_name)

func initialize_enemy(data: EnemyData) -> void:
	visuals.setup(data.character_sprite)
	vitals.setup(data.MaxHP, data.MaxMP)
	Log.info("character ready", data.character_name)
