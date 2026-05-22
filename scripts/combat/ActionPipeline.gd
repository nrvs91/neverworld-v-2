class_name ActionPipeline
extends Node

signal pipeline_complete

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

func run(mnemonic: MnemonicRes, attacker: CombatCharacter, target: CombatCharacter, actors: Array) -> void:
	# Front-loaded null guard — validate before entering async territory.
	# If anything is missing here, pipeline_complete still fires so the FSM never hangs.
	if mnemonic == null or attacker == null or target == null:
		Log.error("ActionPipeline.run — invalid inputs", mnemonic, attacker)
		pipeline_complete.emit()
		return

	var context := ActionContext.new()
	context.mnemonic = mnemonic
	context.source = attacker
	context.target = target

	# Announce and hold for presentation
	CombatEvents.action_announced.emit(mnemonic.mnemonic_name)
	await get_tree().create_timer(0.5).timeout

	# PRE-PASS: direct iteration over all actors' tokens.
	# Each reaction fires with its own clean context. trigger_context points to the primary.
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.PRE_EXECUTION):
			context.pre_queue.append(token)
	for token in context.pre_queue:
		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		token.fire(reaction_ctx)
		token.owner.tokens.remove_token(token)
		if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
			Log.info("ActionPipeline — downed (pre-reaction)", reaction_ctx.target.character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.target)

	# VALIDATE: can the source still execute after pre-reactions?
	if not _can_execute(context):
		if context.negated:
			Log.info("ActionPipeline — primary action negated")
		elif context.cancelled:
			Log.info("ActionPipeline — primary action cancelled")
		CombatEvents.action_resolved.emit(context)
		pipeline_complete.emit()
		return

	# Spend resources — only after validation confirms the action will resolve
	attacker.vitals.spend_ap(mnemonic.ap_cost)
	attacker.vitals.spend_mp(mnemonic.mp_cost)

	# Primary action
	SkillExecutor.execute(context)

	# HP blood cost — paid after execution, not before (it's a price, not a prerequisite)
	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)

	# Downed detection for target
	if context.target.vitals.is_downed():
		Log.info("ActionPipeline — downed", context.target.character_name)
		CombatEvents.actor_downed.emit(context.target)

	# POST-PASS: direct iteration with updated context (any_hit, total_damage, etc. are set).
	# Each reaction fires with its own clean context. trigger_context points to the primary.
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_DAMAGE_TAKEN):
			context.post_queue.append(token)
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_ALLY_HIT):
			context.post_queue.append(token)
	for token in context.post_queue:
		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		token.fire(reaction_ctx)
		token.owner.tokens.remove_token(token)
		if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
			Log.info("ActionPipeline — downed (post-reaction)", reaction_ctx.target.character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.target)

	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
		attacker.character_name, context.target.character_name, context.total_damage])
	CombatEvents.action_resolved.emit(context)
	pipeline_complete.emit()

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

	# TODO: stunned, silenced, frozen checks when status ailments exist
	# if attacker.tokens.has_status("stunned") or attacker.tokens.has_status("silenced"):
	#     context.cancelled = true
	#     return false

	if context.negated:
		return false

	if attacker.vitals.cur_ap < context.mnemonic.ap_cost \
			or attacker.vitals.cur_mp < context.mnemonic.mp_cost:
		context.cancelled = true
		return false

	return true
