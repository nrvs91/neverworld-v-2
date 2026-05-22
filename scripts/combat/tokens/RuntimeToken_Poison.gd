class_name RuntimeToken_Poison
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_START
	token_type = "POISON"

## GDD formula: (max_hp × 10% + max_mp × 10%) × resistance multiplier
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(ResistanceType.DamageType.Nature)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	if resist_mult == 0.0:
		Log.info("RuntimeToken_Poison — IMMUNE", owner.character_name)
		return

	var damage: int = max(1, int((owner.vitals.max_hp * 0.1 + owner.vitals.max_mp * 0.1) * resist_mult))
	Log.info("RuntimeToken_Poison tick", owner.character_name, damage)
	owner.vitals.take_damage(damage)
	context.record_step(true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
