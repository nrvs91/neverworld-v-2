class_name RuntimeToken
extends Resource

enum Trigger {
	INSTANT,
	ON_TURN_START,
	ON_DAMAGE_TAKEN,  # stub — not dispatched yet (COUNTER, BRACE)
	ON_ALLY_HIT,      # stub — not dispatched yet (VIGIL, FOLLOW UP)
	PRE_EXECUTION,    # stub — not dispatched yet (PREMONITION, COVER)
}

var token_type: String = ""
var trigger: Trigger = Trigger.INSTANT
var source: CombatCharacter = null
var owner: CombatCharacter = null

func fire(_context: ActionContext) -> void:
	pass

func tick(_context: ActionContext) -> void:
	pass

func check_trigger(_context: ActionContext) -> bool:
	return false
