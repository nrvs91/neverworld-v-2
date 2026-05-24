class_name RuntimeToken
extends Resource

enum Trigger {
	INSTANT,
	ON_TURN_START,
	ON_TURN_END,
	ON_DAMAGE_TAKEN,
	ON_ALLY_HIT,
	PRE_EXECUTION,
}

var token_type: String = ""
var trigger: Trigger = Trigger.INSTANT
var source: CombatCharacter = null
var owner: CombatCharacter = null
var opposes: String = ""
var skip_first_tick: bool = false

func fire(_context: ActionContext) -> void:
	pass

func tick(_context: ActionContext) -> void:
	pass

func check_trigger(_context: ActionContext) -> bool:
	return false

func get_damage_multiplier() -> float:
	return 1.0
