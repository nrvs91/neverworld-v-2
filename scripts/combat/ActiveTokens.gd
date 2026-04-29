class_name ActiveTokens
extends Node

# Holds active combat tokens for this character.
# Emits signals when tokens are added, removed, or updated.
# Stub — full implementation in a future task.

signal token_added(token: Resource)
signal token_removed(token: Resource)
signal token_updated(token: Resource)

func flush() -> void:
	Log.info("flushed")
