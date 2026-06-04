class_name ActionPipeline
extends Node

signal pipeline_complete

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

func run(mnemonic: MnemonicRes, attacker: CombatCharacter, targets: Array[CombatCharacter], actors: Array) -> void:
	if mnemonic == null or attacker == null or targets.is_empty():
		Log.error("ActionPipeline.run — invalid inputs", mnemonic, attacker)
		pipeline_complete.emit()
		return

	var context := ActionContext.new()
	context.mnemonic = mnemonic
	context.source = attacker
	context.targets = targets

	CombatEvents.action_announced.emit(mnemonic.mnemonic_name)
	await get_tree().create_timer(0.5).timeout

	var pre_tokens: Array = []
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.PRE_EXECUTION):
			pre_tokens.append(token)
	await _run_reaction_pass(pre_tokens, context, false)

	if not _can_execute(context):
		if context.negated:
			Log.info("ActionPipeline — primary action negated")
		elif context.cancelled:
			Log.info("ActionPipeline — primary action cancelled")
		CombatEvents.action_resolved.emit(context)
		pipeline_complete.emit()
		return

	attacker.vitals.spend_ap(mnemonic.ap_cost)
	attacker.vitals.spend_mp(mnemonic.mp_cost)

	SkillExecutor.execute(context)
	CombatEvents.action_executed.emit(context.source, context.targets, context.total_damage, context.mnemonic)

	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)

	for t: CombatCharacter in context.targets:
		if t.vitals.is_downed():
			Log.info("ActionPipeline — downed", t.character_name)
			CombatEvents.actor_downed.emit(t)

	await CombatEvents.action_hit_frame

	_apply_pending_damage(context)
	_show_step_results(context)

	await CombatEvents.action_animation_complete

	var post_tokens: Array = []
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_DAMAGE_TAKEN):
			post_tokens.append(token)
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_ALLY_HIT):
			post_tokens.append(token)
	await _run_reaction_pass(post_tokens, context, true)

	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
		attacker.character_name, context.targets[0].character_name, context.total_damage])
	CombatEvents.action_resolved.emit(context)
	pipeline_complete.emit()

func _run_reaction_pass(tokens: Array, context: ActionContext, announce: bool) -> void:
	for token in tokens:
		if announce:
			CombatEvents.action_announced.emit(token.token_type)
			await get_tree().create_timer(0.5).timeout
		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		token.fire(reaction_ctx)
		_apply_pending_damage(reaction_ctx)
		_show_step_results(reaction_ctx)
		token.owner.tokens.remove_token(token)
		if not reaction_ctx.targets.is_empty() and reaction_ctx.targets[0].vitals.is_downed():
			Log.info("ActionPipeline — downed (reaction)", reaction_ctx.targets[0].character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.targets[0])

## Validation rules, in order:
## 1. Source downed → cancelled (no resource cost)
## 2. Source stunned/silenced/frozen → cancelled (no resource cost)
## 3. Action negated by PRE reaction → negated (resource cost IS spent)
## 4. Insufficient AP/MP after pre-reactions → cancelled (no resource cost)
func _can_execute(context: ActionContext) -> bool:
	var attacker: CombatCharacter = context.source

	if attacker.vitals.is_downed():
		context.cancelled = true
		return false

	if context.negated:
		return false

	if attacker.vitals.cur_ap < context.mnemonic.ap_cost \
			or attacker.vitals.cur_mp < context.mnemonic.mp_cost:
		context.cancelled = true
		return false

	return true

func _apply_pending_damage(context: ActionContext) -> void:
	for entry in context.pending_damage:
		entry.target.vitals.take_damage(entry.damage)
	context.pending_damage.clear()

func _show_step_results(context: ActionContext) -> void:
	for result in context.step_results:
		if result.target == null:
			continue
		if result.hit:
			CombatEvents.combat_text_shown.emit(result.target, str(result.damage))
		else:
			CombatEvents.combat_text_shown.emit(result.target, "MISS")
