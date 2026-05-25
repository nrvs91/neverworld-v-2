class_name RuntimeToken_Counter
extends RuntimeToken

@export var power: int = 15

func _init() -> void:
	trigger = Trigger.ON_DAMAGE_TAKEN
	token_type = "COUNTER"

func check_trigger(context: ActionContext) -> bool:
	return context.target == owner and not context.step_results.is_empty()

func fire(context: ActionContext) -> void:
	var attacker: CombatCharacter = context.trigger_context.source
	var result := CombatCalculator.resolve_hit(
		power,
		ResistanceType.DamageType.Slash,
		5,
		Skill_Effect_Base.ChanceTier.HIGH,
		owner,
		attacker
	)

	if not result.hit:
		Log.info("RuntimeToken_Counter — missed", owner.character_name)
		CombatEvents.combat_text_shown.emit(attacker, "MISS")
		return

	Log.info("RuntimeToken_Counter", "%s->%s %d (crit:%s)" % [
		owner.character_name, attacker.character_name, result.damage, result.is_crit])
	attacker.vitals.take_damage(result.damage)
	CombatEvents.action_executed.emit(owner, attacker, result.damage)
