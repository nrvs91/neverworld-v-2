class_name ActiveTokens
extends Node

const RuntimeToken = preload("res://scripts/combat/tokens/RuntimeToken.gd")
const ActionContext = preload("res://scripts/combat/ActionContext.gd")

signal token_added(token: RuntimeToken)
signal token_removed(token: RuntimeToken)

var _tokens: Array[RuntimeToken] = []

## Append one token instance. If the token opposes an existing type, cancels one of those instead.
func add_token(token: RuntimeToken) -> void:
	if token.opposes != "":
		for i in _tokens.size():
			if _tokens[i].token_type == token.opposes:
				var cancelled := _tokens[i]
				_tokens.remove_at(i)
				Log.info("ActiveTokens — cancelled", token.opposes + " by " + token.token_type)
				token_removed.emit(cancelled)
				return
	_tokens.append(token)
	Log.info("ActiveTokens — added", token.owner.character_name, token.token_type)
	token_added.emit(token)

## Remove a specific token instance (called after it fires or expires).
func remove_token(token: RuntimeToken) -> void:
	_tokens.erase(token)
	Log.info("ActiveTokens — consumed", token.owner.character_name, token.token_type)
	token_removed.emit(token)

func tick_turn_start() -> void:
	_tick_trigger(RuntimeToken.Trigger.ON_TURN_START)

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

func tick_turn_end() -> void:
	_tick_trigger(RuntimeToken.Trigger.ON_TURN_END)

func _tick_trigger(trigger: RuntimeToken.Trigger) -> void:
	var fired_types: Array[String] = []
	var to_tick: Array[RuntimeToken] = []

	for token in _tokens:
		if token.trigger != trigger:
			continue
		if token.token_type in fired_types:
			continue
		fired_types.append(token.token_type)
		to_tick.append(token)

	for token in to_tick:
		if token.skip_first_tick:
			token.skip_first_tick = false
			Log.info("ActiveTokens — cast turn free", token.owner.character_name, token.token_type)
			continue
		var ctx := ActionContext.new()
		token.tick(ctx)
		_tokens.erase(token)
		Log.info("ActiveTokens — expired", token.owner.character_name, token.token_type)
		token_removed.emit(token)

## Removes one token of the given type. Returns true if one was found.
## Used by CombatFSM to consume STUN at turn start.
func consume_if_present(type: String) -> bool:
	for i in _tokens.size():
		if _tokens[i].token_type == type:
			var token := _tokens[i]
			_tokens.remove_at(i)
			Log.info("ActiveTokens — consumed", token.owner.character_name, type)
			token_removed.emit(token)
			return true
	return false

## Returns the combined damage multiplier from all active buff/debuff tokens.
## One modifier applied per token type — quantity is duration, not magnitude.
func get_damage_multiplier() -> float:
	var seen_types: Array[String] = []
	var result: float = 1.0
	for token in _tokens:
		if token.token_type in seen_types:
			continue
		var mult := token.get_damage_multiplier()
		if mult != 1.0:
			result *= mult
			seen_types.append(token.token_type)
	return result

## Returns true if at least one token of the given type is present.
## Used by ActionMenu to check skill preconditions.
func has_token(type: String) -> bool:
	for token in _tokens:
		if token.token_type == type:
			return true
	return false

## Removes ALL tokens of the given type and returns how many were consumed.
## Used by RuntimeToken_Envenom to detonate stacked tokens.
func consume_all(type: String) -> int:
	var count := 0
	for i in range(_tokens.size() - 1, -1, -1):
		if _tokens[i].token_type == type:
			var token := _tokens[i]
			_tokens.remove_at(i)
			token_removed.emit(token)
			count += 1
	if count > 0:
		Log.info("ActiveTokens — consumed all", type, count)
	return count

func flush() -> void:
	_tokens.clear()
	Log.info("ActiveTokens flushed")

func get_tokens() -> Array[RuntimeToken]:
	return _tokens.duplicate(false)
