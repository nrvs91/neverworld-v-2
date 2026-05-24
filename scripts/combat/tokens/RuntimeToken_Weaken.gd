class_name RuntimeToken_Weaken
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_END
	token_type = "WEAKEN"
	opposes = "EMPOWER"

func get_damage_multiplier() -> float:
	return 0.75

func tick(_context: ActionContext) -> void:
	Log.info("RuntimeToken_Weaken — expired", owner.character_name)
