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

## Called with the PRIMARY action context (full — source, targets, any_hit, etc.)
func check_trigger(primary_context: ActionContext) -> bool:
	return false

## Called with a REACTION context. For reaction tokens this is a mostly-empty shell
## with only `trigger_context` (the primary context) populated. Use `reaction_context.trigger_context`
## to read the event that caused this reaction.
func fire(reaction_context: ActionContext) -> void:
	pass

func tick(_context: ActionContext) -> void:
	pass

func get_damage_multiplier() -> float:
	return 1.0
