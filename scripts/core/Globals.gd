# Globals - Autoload Singleton
#
# Global game state and utilities accessible from anywhere.
# Use sparingly - prefer composition over global state.
#
# LOGGING NOTES:
#   - Log.info in _ready confirms autoload initialization order

extends Node

@export var dev_mode := true
@export var version_number: float = 0.01

static var instance
func _ready() -> void:
	instance = self
	
	Log.info("Game started. Initializing...")
	Log.info("Project version:", version_number)
	Log.info("Dev Mode:", dev_mode)
	if dev_mode == true:
		Log.info("Skipping to overworld_scene")

