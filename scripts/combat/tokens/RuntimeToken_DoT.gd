class_name RuntimeToken_DoT
extends RuntimeToken

const ActionContext = preload("res://scripts/combat/ActionContext.gd")

var dot_tag: String = "POISON"
var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Nature

func _init() -> void:
	trigger = Trigger.ON_TURN_START
	token_type = "DOT"  # factory overwrites with "POISON"/"BURN"/"BLEED"; fallback for manual construction

## GDD tick formulas (fixed per dot_tag, not authored per instance):
##   POISON — (max_hp × 10% + max_mp × 10%) × resist_mult
##   BURN   — max_hp × 10% × resist_mult
##   BLEED  — max_hp × 10% × resist_mult
## Context is created fresh per-token by ActiveTokens. mnemonic/source/target are null.
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(damage_type)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	# IMMUNE (resist_mult == 0) — no damage, no broadcast, charges still decrement
	if resist_mult == 0.0:
		Log.info("RuntimeToken_DoT — IMMUNE, tick skipped", owner.character_name)
		return

	var raw: float
	match dot_tag:
		"POISON":
			raw = (owner.vitals.max_hp * 0.1 + owner.vitals.max_mp * 0.1) * resist_mult
		"BURN":
			raw = owner.vitals.max_hp * 0.1 * resist_mult
		"BLEED":
			raw = owner.vitals.max_hp * 0.1 * resist_mult
		_:
			Log.warn("RuntimeToken_DoT — unknown dot_tag", dot_tag)
			return

	var damage: int = max(1, int(raw))
	Log.info("RuntimeToken_DoT tick", "%s %s %d dmg" % [owner.character_name, dot_tag, damage])
	owner.vitals.take_damage(damage)
	context.record_step(true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
