class_name RuntimeToken_Stun
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.INSTANT  # unused — STUN is consumed manually by CombatFSM, not the trigger system
	token_type = "STUN"
