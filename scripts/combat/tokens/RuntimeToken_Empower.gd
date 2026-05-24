class_name RuntimeToken_Empower
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_END
	token_type = "EMPOWER"
	opposes = "WEAKEN"
	skip_first_tick = true

func get_damage_multiplier() -> float:
	return 1.5

func tick(_context: ActionContext) -> void:
	Log.info("RuntimeToken_Empower — expired", owner.character_name)
