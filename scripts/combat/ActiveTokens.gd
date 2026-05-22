class_name ActiveTokens
extends Node

const RuntimeToken = preload("res://scripts/combat/tokens/RuntimeToken.gd")
const ActionContext = preload("res://scripts/combat/ActionContext.gd")

signal token_added(token: RuntimeToken)
signal token_removed(token: RuntimeToken)

var _tokens: Array[RuntimeToken] = []

## Append one token instance. No stacking — multiple tokens of the same type are allowed.
func add_token(token: RuntimeToken) -> void:
	_tokens.append(token)
	Log.info("ActiveTokens — added", token.owner.character_name, token.token_type)
	token_added.emit(token)

## Remove a specific token instance (called after it fires or expires).
func remove_token(token: RuntimeToken) -> void:
	_tokens.erase(token)
	Log.info("ActiveTokens — consumed", token.owner.character_name, token.token_type)
	token_removed.emit(token)

## Fire ONE token per type with ON_TURN_START trigger, then remove it.
## One fresh ActionContext per token — no cross-contamination between ticks.
## Called by CombatFSM at the start of the active actor's turn.
func tick_turn_start() -> void:
	var fired_types: Array[String] = []
	var to_tick: Array[RuntimeToken] = []

	for token in _tokens:
		if token.trigger != RuntimeToken.Trigger.ON_TURN_START:
			continue
		if token.token_type in fired_types:
			continue
		fired_types.append(token.token_type)
		to_tick.append(token)

	for token in to_tick:
		var ctx := ActionContext.new()
		token.tick(ctx)
		_tokens.erase(token)
		Log.info("ActiveTokens — expired", token.owner.character_name, token.token_type)
		token_removed.emit(token)

## Returns display string for card UI. Counts instances per type. Format: "POISON×3 BURN×1"
func get_display_text() -> String:
	if _tokens.is_empty():
		return ""
	var counts: Dictionary = {}
	for token in _tokens:
		counts[token.token_type] = counts.get(token.token_type, 0) + 1
	var parts: Array = []
	for type_name in counts:
		parts.append("%s×%d" % [type_name, counts[type_name]])
	return " ".join(parts)

## Returns ONE token per type whose trigger matches and whose check_trigger passes.
## Only one fires per trigger event — multiple instances of same type queue for future events.
func collect_triggers(context: ActionContext, trigger: RuntimeToken.Trigger) -> Array[RuntimeToken]:
	var result: Array[RuntimeToken] = []
	var seen_types: Array[String] = []
	for token in _tokens:
		if token.trigger != trigger:
			continue
		if token.token_type in seen_types:
			continue
		if token.check_trigger(context):
			result.append(token)
			seen_types.append(token.token_type)
	return result

func flush() -> void:
	_tokens.clear()
	Log.info("ActiveTokens flushed")
