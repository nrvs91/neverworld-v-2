class_name RuntimeToken_Damage
extends RuntimeToken

const ActionContext = preload("res://scripts/combat/ActionContext.gd")
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")

@export var base_damage: int = 0
@export var stat_scalings: Array[StatScaling] = []
@export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
@export var crit_chance: int = 5
@export var chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH
@export var inherit_from_weapon: bool = true
@export var true_strike: bool = false

func _init() -> void:
	token_type = "DAMAGE"
	trigger = Trigger.INSTANT

func fire(context: ActionContext) -> void:
	var effective_type := damage_type
	if CombatCalculator.is_physical(damage_type) and inherit_from_weapon:
		effective_type = _get_weapon_damage_type()

	var result := CombatCalculator.resolve_hit(stat_scalings, base_damage, effective_type, crit_chance, chance_tier, source, owner, true_strike)

	if not result.hit:
		Log.info("RuntimeToken_Damage — missed", "%s->%s" % [source.character_name, owner.character_name])
		context.record_step(owner, false, 0, false)
		return

	var mult_str := "" if result.multiplier == 1.0 else " mult:%.2f" % result.multiplier
	Log.info("RuntimeToken_Damage", "%s->%s %d (crit:%s%s)" % [
		source.character_name, owner.character_name, result.damage, result.is_crit, mult_str])

	context.record_step(owner, true, result.damage, result.is_crit)

static func _get_weapon_damage_type() -> ResistanceType.DamageType:
	# TODO: read from attacker's equipped weapon once gear system exists.
	return ResistanceType.DamageType.Slash
