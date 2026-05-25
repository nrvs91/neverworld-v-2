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

	var result := CombatCalculator.resolve_hit(
		count * power_per_token, damage_type, crit_chance, chance_tier, source, owner)

	if not result.hit:
		Log.info("RuntimeToken_Envenom — missed", source.character_name, owner.character_name)
		CombatEvents.combat_text_shown.emit(owner, "MISS")
		context.record_step(false, 0, false)
		return

	var mult_str := "" if result.multiplier == 1.0 else " mult:%.2f" % result.multiplier
	Log.info("RuntimeToken_Envenom", "%s->%s %d×%d=%d (crit:%s%s)" % [
		source.character_name, owner.character_name,
		count, power_per_token, result.damage, result.is_crit, mult_str])

	owner.vitals.take_damage(result.damage)
	CombatEvents.action_executed.emit(source, owner, result.damage)
	context.record_step(true, result.damage, result.is_crit)
