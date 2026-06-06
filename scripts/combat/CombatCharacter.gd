class_name CombatCharacter
extends Node3D

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")
const BasicAttack = preload("res://resources/mnemonics/basic_attack/basic_attack.tres")

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var stats: StatsComponent = $StatsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visual: CharacterVisualComponent = $CharacterVisualComponent

var character_name: String = ""
var is_player_controlled: bool = false
var mnemonics: Array[MnemonicRes] = []
var resistance_profile: ResistanceProfile = null
var ai_behavior: AIBehaviorComponent = null

func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
	is_player_controlled = true
	var computed := StatCalculator.compute_player(data, save_data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visual.setup(vitals, data.character_sprite)
	character_name = data.character_name
	var base_attack: MnemonicRes = BasicAttack.duplicate() as MnemonicRes
	mnemonics = [base_attack]

	var char_id: String = data.character_name.to_lower()
	for mnemonic in data.mnemonics:
		if mnemonic.usable_by.is_empty():
			mnemonics.append(mnemonic)
			continue
		var usable_by_lowered: Array[String] = []
		for user in mnemonic.usable_by:
			usable_by_lowered.append(user.to_lower())
		if char_id in usable_by_lowered:
			mnemonics.append(mnemonic)
		else:
			Log.info("mnemonic not usable by", "%s not usable by %s" % [mnemonic.mnemonic_name, char_id])
	resistance_profile = ResistanceProfile.new()
	Log.info("character ready", data.character_name)

func initialize_enemy(data: EnemyData) -> void:
	is_player_controlled = false
	var computed := StatCalculator.compute_enemy(data)
	vitals.setup(computed[CharacterStats.Stat.MaxHP], computed[CharacterStats.Stat.MaxMP])
	stats.setup(computed)
	visual.setup(vitals, data.character_sprite)
	character_name = data.character_name
	resistance_profile = data.resistance_profile if data.resistance_profile != null else ResistanceProfile.new()
	var base_attack: MnemonicRes = BasicAttack.duplicate() as MnemonicRes
	if data.basic_attack:
		mnemonics = [base_attack, data.basic_attack]
	else:
		mnemonics = [base_attack]
	ai_behavior = AIBehaviorComponent.new()
	ai_behavior.name = "AIBehaviorComponent"
	add_child(ai_behavior)
	Log.info("character ready", data.character_name)
