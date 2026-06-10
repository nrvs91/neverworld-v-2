class_name ReactionRunner
extends Node


func run_pass(tokens: Array, context: ActionContext, announce: bool) -> void:
	for token in tokens:
		if announce:
			CombatEvents.action_announced.emit(token.token_type)
			await get_tree().create_timer(0.5).timeout

		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		reaction_ctx.source = token.owner
		token.fire(reaction_ctx)

		_apply_pending_damage(reaction_ctx)
		_show_step_results(reaction_ctx)
		token.owner.tokens.remove_token(token)

		for result in reaction_ctx.step_results:
			if result.target != null and result.target.vitals.is_downed():
				Log.info("ReactionRunner — downed", result.target.character_name)
				CombatEvents.actor_downed.emit(result.target)

func _apply_pending_damage(ctx: ActionContext) -> void:
	for entry in ctx.pending_damage:
		entry.target.vitals.take_damage(entry.damage)
	ctx.pending_damage.clear()

func _show_step_results(ctx: ActionContext) -> void:
	for result in ctx.step_results:
		if result.target == null:
			continue
		if result.hit:
			CombatEvents.combat_text_shown.emit(result.target, str(result.damage))
		else:
			CombatEvents.combat_text_shown.emit(result.target, "MISS")
