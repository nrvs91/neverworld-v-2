class_name EnemyData
extends CombatData

const EnemySkillRes = preload("res://scripts/combat/skills/EnemySkill.gd")

@export var xp_value: int = 1
@export var loot_table: LootTable

@export var ai_profile: AIProfile
@export var resistance_profile: ResistanceProfile
@export var skills: Array[EnemySkillRes] = []

@export_group("Basic Attack")
@export var base_attack_damage: int = 10
@export var base_attack_type: ResistanceType.DamageType = ResistanceType.DamageType.Blunt
@export var base_attack_crit_chance: int = 3
@export var base_attack_chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH
