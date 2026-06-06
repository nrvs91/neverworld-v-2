class_name RuntimeToken_Envenom
extends RuntimeToken

const ActionContext = preload("res://scripts/combat/ActionContext.gd")
const StatScalingRes = preload("res://scripts/combat/stats/StatScaling.gd")

@export var consume_type: String = "POISON"
@export var scaling_per_token: float = 1.0
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
		context.record_step(owner, false, 0, false)
		return

	var temp_scalings: Array[StatScaling] = []
	var temp: StatScaling = StatScaling.new()
	temp.stat = CharacterStats.Stat.AtkPhys if CombatCalculator.is_physical(damage_type) else CharacterStats.Stat.AtkMag
	temp.scaling = count * scaling_per_token
	temp_scalings.append(temp)

	var result := CombatCalculator.resolve_hit(
		temp_scalings, damage_type, crit_chance, chance_tier, source, owner)

	if not result.hit:
		Log.info("RuntimeToken_Envenom — missed", source.character_name, owner.character_name)
		context.record_step(owner, false, 0, false)
		return

	var mult_str := "" if result.multiplier == 1.0 else " mult:%.2f" % result.multiplier
	Log.info("RuntimeToken_Envenom", "%s->%s %d×%d=%d (crit:%s%s)" % [
		source.character_name, owner.character_name,
		count, scaling_per_token, result.damage, result.is_crit, mult_str])

	context.record_step(owner, true, result.damage, result.is_crit)
