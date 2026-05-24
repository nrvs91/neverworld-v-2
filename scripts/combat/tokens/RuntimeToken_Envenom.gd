class_name RuntimeToken_Envenom
extends RuntimeToken

const ActionContext = preload("res://scripts/combat/ActionContext.gd")

@export var consume_type: String = "POISON"
@export var power_per_token: int = 30
@export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Nature
@export var crit_chance: int = 5
@export var chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH

func _init() -> void:
	token_type = "ENVENOM"
	trigger = Trigger.INSTANT

func fire(context: ActionContext) -> void:
	var count := owner.tokens.consume_all(consume_type)
	if count == 0:
		Log.warn("RuntimeToken_Envenom — no tokens", owner.character_name)
		context.record_step(false, 0, false)
		return

	var is_phys := _is_physical(damage_type)
	var is_crit := is_phys and CombatCalculator.crit_roll(crit_chance)

	if is_phys and not is_crit:
		var hit_stat := source.stats.stat(CharacterStats.Stat.Hit)
		var dodge_stat := owner.stats.stat(CharacterStats.Stat.Dodge)
		if not CombatCalculator.hit_roll(hit_stat, dodge_stat, chance_tier):
			Log.info("RuntimeToken_Envenom — missed", source.character_name, owner.character_name)
			CombatEvents.combat_text_shown.emit(owner, "MISS")
			context.record_step(false, 0, false)
			return

	var total_power := count * power_per_token
	var atk_stat := CharacterStats.Stat.AtkPhys if is_phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if is_phys else CharacterStats.Stat.DefMag
	var atk := source.stats.stat(atk_stat)
	var def_val := owner.stats.stat(def_stat)
	var raw := CombatCalculator.calc_damage(total_power, atk, def_val)

	if is_crit:
		raw *= 2

	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(damage_type)

	var damage_mult := source.tokens.get_damage_multiplier()
	var final_damage: int = max(0, int(raw * CombatCalculator.resist_multiplier(resist_state) * damage_mult))

	var mult_str := "" if damage_mult == 1.0 else " mult:%.2f" % damage_mult
	Log.info("RuntimeToken_Envenom", "%s->%s %d×%d=%d (crit:%s%s)" % [
		source.character_name, owner.character_name,
		count, power_per_token, final_damage, is_crit, mult_str
	])

	owner.vitals.take_damage(final_damage)
	CombatEvents.action_executed.emit(source, owner, final_damage)
	context.record_step(true, final_damage, is_crit)

static func _is_physical(dt: ResistanceType.DamageType) -> bool:
	return dt in [ResistanceType.DamageType.Slash, ResistanceType.DamageType.Pierce, ResistanceType.DamageType.Blunt]
