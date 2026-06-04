class_name RuntimeToken_Counter
extends RuntimeToken
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")

@export var stat_scalings: Array[StatScaling] = []

func _init() -> void:
	trigger = Trigger.ON_DAMAGE_TAKEN
	token_type = "COUNTER"

func check_trigger(context: ActionContext) -> bool:
	return not context.targets.is_empty() and context.targets[0] == owner and not context.step_results.is_empty()

func fire(context: ActionContext) -> void:
	var attacker: CombatCharacter = context.trigger_context.source
	var result := CombatCalculator.resolve_hit(
		stat_scalings,
		ResistanceType.DamageType.Slash,
		5,
		Skill_Effect_Base.ChanceTier.HIGH,
		owner,
		attacker
	)

	if not result.hit:
		Log.info("RuntimeToken_Counter — missed", owner.character_name)
		context.record_step(attacker, false, 0, false)
		return

	Log.info("RuntimeToken_Counter", "%s->%s %d (crit:%s)" % [
		owner.character_name, attacker.character_name, result.damage, result.is_crit])
	context.record_step(attacker, true, result.damage, result.is_crit)
