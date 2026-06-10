class_name EnemySkill
extends Resource

const SkillEffectBase = preload("res://scripts/combat/skills/effects/Skill_Effect_Base.gd")
const TargetingDataScript = preload("res://scripts/combat/skills/TargetingData.gd")

@export var display_name: String = ""
@export var targeting: TargetingDataScript
@export var effect_steps: Array[SkillEffectBase] = []

@export_group("AI Condition")
@export_range(0, 20) var cooldown_turns: int = 0
@export_range(0.0, 1.0) var hp_threshold: float = 0.0
@export_range(0.0, 100.0) var weight: float = 1.0
