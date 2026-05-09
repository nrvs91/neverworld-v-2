class_name ActiveTokens
extends Node

# Holds active combat tokens for this character.
# Emits signals when tokens are added, removed, or updated.
# Stub — full implementation in a future task.

signal token_added(token: Resource)
signal token_removed(token: Resource)
signal token_updated(token: Resource)

func tick_turn_start() -> void:
	# STUB: tick DoT/HoT, countdown durations, expire tokens.
	# When implementing, define tick order (DoT before HoT? Buffs before Debuffs?) —
	# order affects gameplay outcomes and must be GDD-aligned.
	pass

func flush() -> void:
	Log.info("flushed")
