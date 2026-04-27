extends Node

@onready var env_wrapper = $EnvWrapper

func _ready() -> void:
	print("Spike: EnvWrapper enabled. Box should be pink-tinted.")
	print("Spike: waiting 5 seconds...")
	await get_tree().create_timer(5.0).timeout
	env_wrapper.process_mode = Node.PROCESS_MODE_DISABLED
	print("Spike: EnvWrapper is now PROCESS_MODE_DISABLED. Does the box stay lit?")
