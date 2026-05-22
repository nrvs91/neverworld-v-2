class_name SkillExecutor

static func execute(context: ActionContext) -> void:
	for effect in context.mnemonic.effect_steps:
		if effect.needs_previous_hit and not context.any_hit:
			context.record_step(false, 0, false)
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
		Log.error("SkillExecutor — Skill_Effect_Instant has no token", context.mnemonic.mnemonic_name)
		return
	var token := effect.token.duplicate(true) as RuntimeToken
	token.source = context.source
	token.owner = context.target
	token.fire(context)

static func _grant_tokens(effect: Skill_Effect_Grant, context: ActionContext) -> void:
	if effect.token == null:
		Log.error("SkillExecutor — Skill_Effect_Grant has no token", context.mnemonic.mnemonic_name)
		return
	for i in range(effect.amount):
		var token := effect.token.duplicate(true) as RuntimeToken
		token.source = context.source
		token.owner = context.target
		context.target.tokens.add_token(token)
		context.tokens_applied.append(token)

static func _remove_tokens(effect: Skill_Effect_Remove, context: ActionContext) -> void:
	Log.warn("SkillExecutor — Skill_Effect_Remove not yet wired", effect.token_type)
