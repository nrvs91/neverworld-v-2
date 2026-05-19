class_name ActiveTokens
extends Node

const RuntimeToken = preload("res://scripts/combat/tokens/RuntimeToken.gd")
const ActionContext = preload("res://scripts/combat/ActionContext.gd")

signal token_added(token: RuntimeToken)
signal token_removed(token: RuntimeToken)
signal token_updated(token: RuntimeToken)

const CHARGES_CAP: int = 9

var _tokens: Array[RuntimeToken] = []

func add_token(token: RuntimeToken) -> void:
	for existing in _tokens:
		if existing.token_type == token.token_type:
			var prev: int = existing.charges
			existing.charges = min(existing.charges + token.charges, CHARGES_CAP)
			Log.info("ActiveTokens — extended", "%s %d->%d" % [token.token_type, prev, existing.charges])
			token_updated.emit(existing)
			return
	_tokens.append(token)
	Log.info("ActiveTokens — added", "%s %s" % [token.owner.character_name, token.token_type])
	token_added.emit(token)

## Fire all ON_TURN_START tokens, decrement charges, remove expired ones.
## One fresh ActionContext per token — no cross-contamination between ticks.
## Called by CombatFSM at the start of the active actor's turn.
func tick_turn_start() -> void:
	var to_remove: Array[RuntimeToken] = []
	for token in _tokens:
		if token.trigger != RuntimeToken.Trigger.ON_TURN_START:
			continue
		var ctx := ActionContext.new()
		token.tick(ctx)
		token.charges -= 1
		if token.charges <= 0:
			to_remove.append(token)
		else:
			token_updated.emit(token)
	for token in to_remove:
		_tokens.erase(token)
		Log.info("ActiveTokens — expired", "%s %s" % [token.owner.character_name, token.token_type])
		token_removed.emit(token)

## Returns a display string for the card UI. Format: "POISON×3 BURN×2"
func get_display_text() -> String:
	if _tokens.is_empty():
		return ""
	var parts: Array = []
	for token in _tokens:
		parts.append("%s×%d" % [token.token_type, token.charges])
	return " ".join(parts)

func flush() -> void:
	_tokens.clear()
	Log.info("ActiveTokens flushed")
