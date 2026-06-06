class_name MnemonicResource
extends Resource

const TargetingDataScript = preload("res://scripts/combat/skills/TargetingData.gd")
const SkillEffectBase = preload("res://scripts/combat/skills/effects/Skill_Effect_Base.gd")

@export var mnemonic_name: String = ""
@export var ap_generates: int = 0
@export_range(0, 9) var ap_cost: int = 0
@export var ap_generation_bonuses: Dictionary = {}
@export var ap_reduction_conditions: Dictionary = {}
@export var mp_cost: int = 0
@export var hp_cost_percent: float = 0.0
@export var rank: int = 1
@export var usable_by: Array[String] = []
@export var is_melee: bool = true
@export var merge_display: bool = true
@export var targeting: TargetingDataScript
@export var effect_steps: Array[SkillEffectBase] = []
@export var requires_token_on_enemy: String = ""
