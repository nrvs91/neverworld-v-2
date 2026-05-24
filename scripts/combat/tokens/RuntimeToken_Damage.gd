class_name RuntimeToken_Damage
extends RuntimeToken

const ActionContext = preload("res://scripts/combat/ActionContext.gd")

@export var power: int = 10
@export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
@export var crit_chance: int = 5
@export var chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH
@export var inherit_from_weapon: bool = true
@export var true_strike: bool = false

func _init() -> void:
	token_type = "DAMAGE"
	trigger = Trigger.INSTANT

func fire(context: ActionContext) -> void:
	var is_phys: bool = _is_physical(damage_type)

	var is_crit: bool = CombatCalculator.crit_roll(crit_chance)

	if is_phys and not is_crit and not true_strike:
		var hit_stat: int = source.stats.stat(CharacterStats.Stat.Hit)
		var dodge_stat: int = owner.stats.stat(CharacterStats.Stat.Dodge)
		if not CombatCalculator.hit_roll(hit_stat, dodge_stat, chance_tier):
			Log.info("RuntimeToken_Damage — missed", "%s->%s" % [source.character_name, owner.character_name])
			CombatEvents.combat_text_shown.emit(owner, "MISS")
			context.record_step(false, 0, false)
			return

	var effective_type: ResistanceType.DamageType = damage_type
	if is_phys and inherit_from_weapon:
		effective_type = _get_weapon_damage_type()

	var atk_stat := CharacterStats.Stat.AtkPhys if is_phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if is_phys else CharacterStats.Stat.DefMag
	var atk: int = source.stats.stat(atk_stat)
	var def_val: int = owner.stats.stat(def_stat)
	var raw: int = CombatCalculator.calc_damage(power, atk, def_val)

	if is_crit:
		raw *= 2

	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(effective_type)
	var damage_mult: float = source.tokens.get_damage_multiplier()
	var final_damage: int = max(0, int(raw * CombatCalculator.resist_multiplier(resist_state) * damage_mult))

	var mult_str := "" if damage_mult == 1.0 else " mult:%.2f" % damage_mult
	var summary := "%s->%s %d (crit:%s resist:%s%s)" % [source.character_name, owner.character_name,
		final_damage, is_crit, ResistanceType.State.keys()[resist_state], mult_str]
	Log.info("RuntimeToken_Damage", summary)

	owner.vitals.take_damage(final_damage)
	CombatEvents.action_executed.emit(source, owner, final_damage)
	context.record_step(true, final_damage, is_crit)

static func _is_physical(dt: ResistanceType.DamageType) -> bool:
	return dt == ResistanceType.DamageType.Slash \
		or dt == ResistanceType.DamageType.Pierce \
		or dt == ResistanceType.DamageType.Blunt

static func _get_weapon_damage_type() -> ResistanceType.DamageType:
	# TODO: read from attacker's equipped weapon once gear system exists.
	return ResistanceType.DamageType.Slash
