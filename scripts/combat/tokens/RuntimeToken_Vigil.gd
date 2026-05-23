class_name RuntimeToken_Vigil
extends RuntimeToken

@export var power: int = 15

func _init() -> void:
	trigger = Trigger.ON_ALLY_HIT
	token_type = "VIGIL"

func check_trigger(context: ActionContext) -> bool:
	return context.any_hit \
		and context.target.is_player_controlled == owner.is_player_controlled

func fire(context: ActionContext) -> void:
	var target: CombatCharacter = context.trigger_context.target
	var atk: int = owner.stats.stat(CharacterStats.Stat.AtkMag)
	var amount: int = CombatCalculator.calc_damage(power, atk, 0)

	Log.info("RuntimeToken_Vigil", "%s heals %s %d" % [owner.character_name, target.character_name, amount])
	target.vitals.heal(amount)
	CombatEvents.combat_text_shown.emit(target, "HEAL +%d" % amount)
