class_name EnemyData
extends CombatData

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

@export var xp_value: int = 1
@export var loot_table: LootTable

@export var ai_profile: AIProfile
@export var resistance_profile: ResistanceProfile
@export var basic_attack: MnemonicRes
