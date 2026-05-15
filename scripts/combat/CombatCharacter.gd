class_name CombatCharacter
extends Node3D

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var stats: StatsComponent = $StatsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visuals: CombatVisuals = $CombatVisuals
@onready var sfx: CombatSFXComponent = $CombatSFXComponent

var character_name: String = ""
var is_player_controlled: bool = false
var mnemonics: Array[MnemonicRes] = []
var resistance_profile: ResistanceProfile = null

func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
	is_player_controlled = true
	var computed := StatCalculator.compute_player(data, save_data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visuals.setup(data.character_sprite)
	character_name = data.character_name
	mnemonics = data.mnemonics
	resistance_profile = ResistanceProfile.new()
	Log.info("character ready", data.character_name)

func initialize_enemy(data: EnemyData) -> void:
	is_player_controlled = false
	var computed := StatCalculator.compute_enemy(data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visuals.setup(data.character_sprite)
	character_name = data.character_name
	resistance_profile = data.resistance_profile if data.resistance_profile != null else ResistanceProfile.new()
	if data.basic_attack:
		mnemonics = [data.basic_attack]
	Log.info("character ready", data.character_name)
