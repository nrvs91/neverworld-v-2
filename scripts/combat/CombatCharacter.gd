class_name CombatCharacter
extends Node3D

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var stats: StatsComponent = $StatsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visuals: CombatVisuals = $CombatVisuals
@onready var sfx: CombatSFXComponent = $CombatSFXComponent

var character_name: String = ""

func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
	var computed := StatCalculator.compute_player(data, save_data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visuals.setup(data.character_sprite)
	character_name = data.character_name
	Log.info("character ready", data.character_name)

func initialize_enemy(data: EnemyData) -> void:
	var computed := StatCalculator.compute_enemy(data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visuals.setup(data.character_sprite)
	character_name = data.character_name
	Log.info("character ready", data.character_name)
