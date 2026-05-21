class_name SkillExecutor
## Token factory. Creates RuntimeToken instances from a mnemonic's effect steps.
## Receives an ActionContext created by CombatFSM — does not create its own.

const RuntimeToken = preload("res://scripts/combat/tokens/RuntimeToken.gd")
const RuntimeToken_Damage = preload("res://scripts/combat/tokens/RuntimeToken_Damage.gd")
const RuntimeToken_DoT = preload("res://scripts/combat/tokens/RuntimeToken_DoT.gd")
const SkillEffectDamage = preload("res://scripts/combat/skills/effects/Skill_Effect_Damage.gd")
const SkillEffectDoT = preload("res://scripts/combat/skills/effects/Skill_Effect_DoT.gd")
const Skill_Effect_Base = preload("res://scripts/combat/skills/effects/Skill_Effect_Base.gd")

static func execute(context: ActionContext) -> void:
	for effect in context.mnemonic.effect_steps:
		if effect.needs_previous_hit and not context.any_hit:
			context.record_step(false, 0, false)
			continue

		var token: RuntimeToken = _create_token(effect, context.source, context.target)
		if token == null:
			continue

		if token.trigger == RuntimeToken.Trigger.INSTANT:
			token.fire(context)
		else:
			# TODO: TargetingData.shape is authored but not consumed here.
			# All persistent effects attach to context.target regardless of shape.
			# Wire TargetingData before authoring any AoE, SELF, or filter-targeted skills.
			context.target.tokens.add_token(token)
			context.tokens_applied.append(token)

static func _create_token(effect: Skill_Effect_Base, attacker: CombatCharacter, target: CombatCharacter) -> RuntimeToken:
	if effect is SkillEffectDamage:
		return _create_damage_token(effect as SkillEffectDamage, attacker, target)
	if effect is SkillEffectDoT:
		return _create_dot_token(effect as SkillEffectDoT, attacker, target)
	Log.warn("SkillExecutor — unknown effect type", effect.get_class())
	var fallback := RuntimeToken.new()
	fallback.source = attacker
	fallback.owner = target
	return fallback

static func _create_damage_token(effect: SkillEffectDamage, attacker: CombatCharacter, target: CombatCharacter) -> RuntimeToken_Damage:
	var token := RuntimeToken_Damage.new()
	token.source = attacker
	token.owner = target
	token.power = effect.power
	token.damage_type = effect.damage_type
	token.crit_chance = effect.crit_chance
	token.chance_tier = effect.chance_tier
	token.inherit_from_weapon = effect.inherit_from_weapon
	token.true_strike = effect.true_strike
	return token

static func _create_dot_token(effect: SkillEffectDoT, attacker: CombatCharacter, target: CombatCharacter) -> RuntimeToken_DoT:
	var token := RuntimeToken_DoT.new()
	token.source = attacker
	token.owner = target
	token.charges = effect.charges
	match effect.dot_tag:
		Skill_Effect_DoT.DotTag.POISON:
			token.dot_tag = "POISON"
			token.token_type = "POISON"
			token.damage_type = ResistanceType.DamageType.Nature
		Skill_Effect_DoT.DotTag.BURN:
			token.dot_tag = "BURN"
			token.token_type = "BURN"
			token.damage_type = ResistanceType.DamageType.Fire
		Skill_Effect_DoT.DotTag.BLEED:
			token.dot_tag = "BLEED"
			token.token_type = "BLEED"
			token.damage_type = ResistanceType.DamageType.Bleed
		_:
			Log.warn("SkillExecutor — unhandled DotTag", str(effect.dot_tag))
			return null
	return token
