class_name RuntimeToken_Vigil
extends RuntimeToken
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")

@export var stat_scalings: Array[StatScaling] = []

func _init() -> void:
	trigger = Trigger.ON_ALLY_HIT
	token_type = "VIGIL"

func check_trigger(context: ActionContext) -> bool:
	return context.any_hit \
		and not context.targets.is_empty() and context.targets[0].is_player_controlled == owner.is_player_controlled

func fire(context: ActionContext) -> void:
	var target: CombatCharacter = context.trigger_context.targets[0]
	var amount: int = CombatCalculator.calc_damage(stat_scalings, owner.stats, 0)

	Log.info("RuntimeToken_Vigil", "%s heals %s %d" % [owner.character_name, target.character_name, amount])
	target.vitals.heal(amount)
	CombatEvents.combat_text_shown.emit(target, "HEAL +%d" % amount)
