class_name SkillExecutor

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")
const EnemySkillRes = preload("res://scripts/combat/skills/EnemySkill.gd")

static func _skill_name(mnemonic: Resource) -> String:
	if mnemonic is MnemonicRes:
		return mnemonic.mnemonic_name
	if mnemonic is EnemySkillRes:
		return mnemonic.display_name
	return ""

static func execute(context: ActionContext) -> void:
	for effect in context.mnemonic.effect_steps:
		if effect.needs_previous_hit and not context.any_hit:
			context.record_step(null, false, 0, false)
			continue

		if effect is Skill_Effect_Instant:
			_fire_instant(effect, context)
		elif effect is Skill_Effect_Grant:
			_grant_tokens(effect, context)
		elif effect is Skill_Effect_Remove:
			_remove_tokens(effect, context)
		else:
			Log.warn("SkillExecutor — unknown effect type", effect.get_class())

static func _fire_instant(effect: Skill_Effect_Instant, context: ActionContext) -> void:
	if effect.token == null:
		Log.error("SkillExecutor — Skill_Effect_Instant has no token", _skill_name(context.mnemonic))
		return
	for target in context.targets:
		var token := effect.token.duplicate(true) as RuntimeToken
		token.source = context.source
		token.owner = target
		token.fire(context)

static func _grant_tokens(effect: Skill_Effect_Grant, context: ActionContext) -> void:
	if effect.token == null:
		Log.error("SkillExecutor — Skill_Effect_Grant has no token", _skill_name(context.mnemonic))
		return
	for target in context.targets:
		for i in range(effect.amount):
			var token := effect.token.duplicate(true) as RuntimeToken
			token.source = context.source
			token.owner = target
			target.tokens.add_token(token)
			context.tokens_applied.append(token)

static func _remove_tokens(effect: Skill_Effect_Remove, context: ActionContext) -> void:
	Log.warn("SkillExecutor — Skill_Effect_Remove not yet wired", effect.token_type)
