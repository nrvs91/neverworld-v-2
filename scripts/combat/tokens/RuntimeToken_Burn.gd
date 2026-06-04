class_name RuntimeToken_Burn
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_START
	token_type = "BURN"

## GDD formula: max_hp × 10% × resistance multiplier
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(ResistanceType.DamageType.Fire)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	if resist_mult == 0.0:
		Log.info("RuntimeToken_Burn — IMMUNE", owner.character_name)
		return

	var damage: int = max(1, int(owner.vitals.max_hp * 0.1 * resist_mult))
	Log.info("RuntimeToken_Burn tick", owner.character_name, damage)
	context.record_step(owner, true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
