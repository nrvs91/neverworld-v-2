# Globals - Autoload Singleton
#
# Global game state and utilities accessible from anywhere.
# Use sparingly - prefer composition over global state.
#
# LOGGING NOTES:
#   - Log.info in _ready confirms autoload initialization order

extends Node

static var instance
func _ready() -> void:
	instance = self
	
	Log.info("Initializing...")
