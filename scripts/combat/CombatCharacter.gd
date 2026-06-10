class_name CombatCharacter
extends Node3D

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")
const EnemySkillRes = preload("res://scripts/combat/skills/EnemySkill.gd")
const BasicAttack = preload("res://resources/mnemonics/basic_attack/basic_attack.tres")

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var stats: StatsComponent = $StatsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visual: CharacterVisualComponent = $CharacterVisualComponent

var character_name: String = ""
var is_player_controlled: bool = false
var mnemonics: Array[MnemonicRes] = []
var enemy_skills: Array[EnemySkillRes] = []
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
	vitals.setup(computed[CharacterStats.Stat.MaxHP], 0)
	stats.setup(computed)
	visual.setup(vitals, data.character_sprite)
	character_name = data.character_name
	resistance_profile = data.resistance_profile if data.resistance_profile != null else ResistanceProfile.new()

	var basic_skill := EnemySkillRes.new()
	basic_skill.display_name = "Attack"

	var targeting := TargetingData.new()
	targeting.shape = TargetingData.Shape.SINGLE_ENEMY
	basic_skill.targeting = targeting

	var damage_token := RuntimeToken_Damage.new()
	damage_token.base_damage = data.base_attack_damage
	damage_token.damage_type = data.base_attack_type
	damage_token.crit_chance = data.base_attack_crit_chance
	damage_token.inherit_from_weapon = false
	damage_token.chance_tier = data.base_attack_chance_tier

	var effect := Skill_Effect_Instant.new()
	effect.token = damage_token
	basic_skill.effect_steps = [effect]

	enemy_skills = [basic_skill]
	for skill in data.skills:
		enemy_skills.append(skill)
	ai_behavior = AIBehaviorComponent.new()
	ai_behavior.name = "AIBehaviorComponent"
	add_child(ai_behavior)
	Log.info("character ready", data.character_name)
