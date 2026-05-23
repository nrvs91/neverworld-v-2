class_name RuntimeToken_Counter
extends RuntimeToken

@export var power: int = 15

func _init() -> void:
	trigger = Trigger.ON_DAMAGE_TAKEN
	token_type = "COUNTER"

func check_trigger(context: ActionContext) -> bool:
	return context.target == owner and not context.step_results.is_empty()

func fire(context: ActionContext) -> void:
	var attacker: CombatCharacter = context.trigger_context.source

	var is_crit: bool = CombatCalculator.crit_roll(5)

	if not is_crit:
		var hit_stat: int = owner.stats.stat(CharacterStats.Stat.Hit)
		var dodge_stat: int = attacker.stats.stat(CharacterStats.Stat.Dodge)
		if not CombatCalculator.hit_roll(hit_stat, dodge_stat, Skill_Effect_Base.ChanceTier.HIGH):
			Log.info("RuntimeToken_Counter — missed", owner.character_name)
			CombatEvents.combat_text_shown.emit(attacker, "MISS")
			return

	var atk: int = owner.stats.stat(CharacterStats.Stat.AtkPhys)
	var def_val: int = attacker.stats.stat(CharacterStats.Stat.DefPhys)
	var raw: int = CombatCalculator.calc_damage(power, atk, def_val)

	if is_crit:
		raw *= 2

	var resist_state := ResistanceType.State.NONE
	if attacker.resistance_profile != null:
		resist_state = attacker.resistance_profile.get_state(ResistanceType.DamageType.Slash)
	var final_damage: int = max(0, int(raw * CombatCalculator.resist_multiplier(resist_state)))

	Log.info("RuntimeToken_Counter", "%s->%s %d (crit:%s)" % [
		owner.character_name, attacker.character_name, final_damage, is_crit])
	attacker.vitals.take_damage(final_damage)
	CombatEvents.action_executed.emit(owner, attacker, final_damage)
