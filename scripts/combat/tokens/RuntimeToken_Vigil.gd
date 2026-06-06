class_name RuntimeToken_Vigil
extends RuntimeToken
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")

@export var stat_scalings: Array[StatScaling] = []

func _init() -> void:
	trigger = Trigger.ON_ALLY_HIT
	token_type = "VIGIL"

func check_trigger(primary_context: ActionContext) -> bool:
	if not primary_context.any_hit:
		return false
	for target: CombatCharacter in primary_context.targets:
		if target.is_player_controlled == owner.is_player_controlled:
			return true
	return false

func fire(reaction_context: ActionContext) -> void:
	var primary := reaction_context.trigger_context
	var amount: int = CombatCalculator.calc_damage(stat_scalings, owner.stats, 0)

	for target: CombatCharacter in primary.targets:
		if target.is_player_controlled != owner.is_player_controlled:
			continue
		Log.info("RuntimeToken_Vigil", "%s heals %s %d" % [owner.character_name, target.character_name, amount])
		target.vitals.heal(amount)
		CombatEvents.combat_text_shown.emit(target, "HEAL +%d" % amount)
