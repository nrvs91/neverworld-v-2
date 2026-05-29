class_name ActionPipeline
extends Node

signal pipeline_complete

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

@onready var vfx_container: Node3D = get_parent().get_node_or_null("VFXContainer")

var _context: ActionContext = null

func _ready() -> void:
	if vfx_container == null:
		Log.error("ActionPipeline — VFXContainer not found as sibling, VFX spawning will fail")
	else:
		Log.info("ActionPipeline — VFXContainer linked")
func run(mnemonic: MnemonicRes, attacker: CombatCharacter, target: CombatCharacter, actors: Array) -> void:
	if mnemonic == null or attacker == null or target == null:
		Log.error("ActionPipeline.run — invalid inputs", mnemonic, attacker)
		pipeline_complete.emit()
		return

	var context := ActionContext.new()
	context.mnemonic = mnemonic
	context.source = attacker
	context.target = target
	_context = context

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

	if mnemonic.is_melee:
		var target_slot_pos: Vector3 = target.get_parent().global_position
		var presenter := attacker.presenter
		var anim_player := attacker.anim_player
		var data := mnemonic.presentation
		presenter.configure(data, context, target_slot_pos, vfx_container)
		presenter.impact_triggered.connect(_on_impact)
		anim_player.play("attack_skeleton")
		await anim_player.animation_finished
		if presenter.impact_triggered.is_connected(_on_impact):
			presenter.impact_triggered.disconnect(_on_impact)
	else:
		SkillExecutor.execute(context)
		CombatEvents.action_executed.emit(context.source, context.target, context.total_damage)

	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)

	if context.target.vitals.is_downed():
		Log.info("ActionPipeline — downed", context.target.character_name)
		CombatEvents.actor_downed.emit(context.target)

	await get_tree().create_timer(0.4).timeout

	var post_tokens: Array = []
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_DAMAGE_TAKEN):
			post_tokens.append(token)
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_ALLY_HIT):
			post_tokens.append(token)
	await _run_reaction_pass(post_tokens, context, true)

	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
		attacker.character_name, context.target.character_name, context.total_damage])
	CombatEvents.action_resolved.emit(context)
	pipeline_complete.emit()

func _on_impact() -> void:
	if _context == null:
		Log.error("ActionPipeline._on_impact — _context was null")
		return
	SkillExecutor.execute(_context)
	CombatEvents.action_executed.emit(_context.source, _context.target, _context.total_damage)

func _run_reaction_pass(tokens: Array, context: ActionContext, announce: bool) -> void:
	for token in tokens:
		if announce:
			CombatEvents.action_announced.emit(token.token_type)
			await get_tree().create_timer(0.5).timeout
		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		token.fire(reaction_ctx)
		token.owner.tokens.remove_token(token)
		if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
			Log.info("ActionPipeline — downed (reaction)", reaction_ctx.target.character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.target)

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
