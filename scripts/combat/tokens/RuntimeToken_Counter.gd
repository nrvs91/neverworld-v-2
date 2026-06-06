class_name RuntimeToken_Counter
extends RuntimeToken
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")

@export var stat_scalings: Array[StatScaling] = []

func _init() -> void:
	trigger = Trigger.ON_DAMAGE_TAKEN
	token_type = "COUNTER"

func check_trigger(primary_context: ActionContext) -> bool:
	return primary_context.any_hit and owner in primary_context.targets

func fire(reaction_context: ActionContext) -> void:
	var attacker: CombatCharacter = reaction_context.trigger_context.source
	var result := CombatCalculator.resolve_hit(
		stat_scalings,
		0,
		ResistanceType.DamageType.Slash,
		5,
		Skill_Effect_Base.ChanceTier.HIGH,
		owner,
		attacker
	)

	if not result.hit:
		Log.info("RuntimeToken_Counter — missed", owner.character_name)
		reaction_context.record_step(attacker, false, 0, false)
		return

	Log.info("RuntimeToken_Counter", "%s->%s %d (crit:%s)" % [
		owner.character_name, attacker.character_name, result.damage, result.is_crit])
	reaction_context.record_step(attacker, true, result.damage, result.is_crit)
