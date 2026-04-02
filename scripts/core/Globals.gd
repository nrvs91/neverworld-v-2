extends Node

static var instance
func _ready() -> void:
	instance = self
	
	Log.info("Initializing...")
