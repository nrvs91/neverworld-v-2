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

	var effective_cost: int = _effective_ap_cost(mnemonic, context.token_snapshot)
	attacker.vitals.spend_ap(effective_cost)
	attacker.vitals.spend_mp(mnemonic.mp_cost)

	var total_generation: int = _total_ap_generation(mnemonic, context.token_snapshot)
	if total_generation > 0:
		attacker.vitals.gain_ap(total_generation)

	Log.info("ActionPipeline — AP cost: %d, generated: %d, total: %d" % [effective_cost, total_generation, attacker.vitals.cur_ap])

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

func _can_execute(context: ActionContext) -> bool:
	var attacker: CombatCharacter = context.source

	if attacker.vitals.is_downed():
		context.cancelled = true
		return false

	if context.negated:
		return false

	if not context.mnemonic.ap_reduction_conditions.is_empty() or not context.mnemonic.ap_generation_bonuses.is_empty():
		context.token_snapshot = _snapshot_target_tokens(context.targets)

	var effective_cost: int = _effective_ap_cost(context.mnemonic, context.token_snapshot)

	if attacker.vitals.cur_ap < effective_cost \
			or attacker.vitals.cur_mp < context.mnemonic.mp_cost:
		context.cancelled = true
		return false

	return true

func _effective_ap_cost(mnemonic: MnemonicRes, token_snapshot: Dictionary) -> int:
	if mnemonic.ap_cost <= 0:
		return 0
	var discount: int = 0
	if not mnemonic.ap_reduction_conditions.is_empty():
		for token_type in mnemonic.ap_reduction_conditions:
			var per_token_discount: int = mnemonic.ap_reduction_conditions[token_type]
			var count: int = token_snapshot.get(token_type, 0)
			discount += per_token_discount * count
	return max(0, mnemonic.ap_cost - discount)

func _total_ap_generation(mnemonic: MnemonicRes, token_snapshot: Dictionary) -> int:
	var total: int = mnemonic.ap_generates
	if not mnemonic.ap_generation_bonuses.is_empty():
		for token_type in mnemonic.ap_generation_bonuses:
			var per_token_bonus: int = mnemonic.ap_generation_bonuses[token_type]
			var count: int = token_snapshot.get(token_type, 0)
			total += per_token_bonus * count
	return total

func _snapshot_target_tokens(targets: Array[CombatCharacter]) -> Dictionary:
	var counts: Dictionary = {}
	for t: CombatCharacter in targets:
		for token in t.tokens.get_tokens():
			var tt: String = token.token_type
			counts[tt] = counts.get(tt, 0) + 1
	return counts

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
