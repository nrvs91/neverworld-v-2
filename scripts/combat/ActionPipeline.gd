class_name ActionPipeline
extends Node

signal pipeline_complete

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")
const ReactionRunnerScript = preload("res://scripts/combat/ReactionRunner.gd")

var _context: ActionContext = null
var _actors: Array = []
var _reaction_runner: ReactionRunnerScript = null

func _ready() -> void:
	_reaction_runner = ReactionRunnerScript.new()
	_reaction_runner.name = "ReactionRunner"
	add_child(_reaction_runner)

func run(mnemonic: Resource, attacker: CombatCharacter, targets: Array[CombatCharacter], actors: Array) -> void:
	if not _init_run(mnemonic, attacker, targets, actors):
		pipeline_complete.emit()
		return

	CombatEvents.action_announced.emit(_skill_name(mnemonic))
	await get_tree().create_timer(0.5).timeout

	await _phase_pre_reactions()

	if not _validate_and_pay_costs():
		_finish_aborted()
		return

	_phase_primary_execution()
	_check_downed(_context.targets, "pre-hit")

	await _phase_hit_and_animation()

	await _phase_post_reactions()

	_finish_resolved()

func _init_run(mnemonic: Resource, attacker: CombatCharacter, targets: Array[CombatCharacter], actors: Array) -> bool:
	if mnemonic == null or attacker == null or targets.is_empty():
		Log.error("ActionPipeline.run — invalid inputs", mnemonic, attacker)
		return false

	_context = ActionContext.new()
	_context.mnemonic = mnemonic
	_context.source = attacker
	_context.targets = targets
	_actors = actors
	return true

func _phase_pre_reactions() -> void:
	var pre_tokens: Array = []
	for actor: CombatCharacter in _actors:
		for token in actor.tokens.collect_triggers(_context, RuntimeToken.Trigger.PRE_EXECUTION):
			pre_tokens.append(token)
	await _reaction_runner.run_pass(pre_tokens, _context, false)

func _validate_and_pay_costs() -> bool:
	var attacker: CombatCharacter = _context.source

	if attacker.vitals.is_downed():
		_context.cancelled = true
		return false

	if _context.negated:
		return false

	var ap_reduction_conditions: Dictionary = _ap_reduction_conditions(_context.mnemonic)
	var ap_generation_bonuses: Dictionary = _ap_generation_bonuses(_context.mnemonic)
	if not ap_reduction_conditions.is_empty() or not ap_generation_bonuses.is_empty():
		_context.token_snapshot = CombatCalculator.snapshot_target_tokens(_context.targets)

	var effective_cost: int = CombatCalculator.effective_ap_cost(_context.mnemonic, _context.token_snapshot)

	if attacker.vitals.cur_ap < effective_cost \
			or attacker.vitals.cur_mp < _mp_cost(_context.mnemonic):
		_context.cancelled = true
		return false

	attacker.vitals.spend_ap(effective_cost)
	attacker.vitals.spend_mp(_mp_cost(_context.mnemonic))

	var total_generation: int = CombatCalculator.total_ap_generation(_context.mnemonic, _context.token_snapshot)
	if total_generation > 0:
		attacker.vitals.gain_ap(total_generation)

	Log.info("ActionPipeline — AP cost: %d, generated: %d, total: %d" % [effective_cost, total_generation, attacker.vitals.cur_ap])

	return true

func _phase_primary_execution() -> void:
	SkillExecutor.execute(_context)
	CombatEvents.action_executed.emit(_context.source, _context.targets, _context.total_damage, _context.mnemonic)

	var hp_cost_percent: float = _hp_cost_percent(_context.mnemonic)
	if hp_cost_percent > 0.0:
		_context.source.vitals.spend_hp_percent(hp_cost_percent)

func _phase_hit_and_animation() -> void:
	await CombatEvents.action_hit_frame
	_apply_pending_damage(_context)
	_show_step_results(_context)
	await CombatEvents.action_animation_complete

func _phase_post_reactions() -> void:
	var post_tokens: Array = []
	for actor: CombatCharacter in _actors:
		for token in actor.tokens.collect_triggers(_context, RuntimeToken.Trigger.ON_DAMAGE_TAKEN):
			post_tokens.append(token)
		for token in actor.tokens.collect_triggers(_context, RuntimeToken.Trigger.ON_ALLY_HIT):
			post_tokens.append(token)
	await _reaction_runner.run_pass(post_tokens, _context, true)

func _finish_resolved() -> void:
	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
		_context.source.character_name, _context.targets[0].character_name, _context.total_damage])
	CombatEvents.action_resolved.emit(_context)
	pipeline_complete.emit()

func _finish_aborted() -> void:
	if _context.negated:
		Log.info("ActionPipeline — primary action negated")
	elif _context.cancelled:
		Log.info("ActionPipeline — primary action cancelled")
	CombatEvents.action_resolved.emit(_context)
	pipeline_complete.emit()

func _check_downed(targets: Array[CombatCharacter], reason: String) -> void:
	for t: CombatCharacter in targets:
		if t.vitals.is_downed():
			Log.info("ActionPipeline — downed", t.character_name, reason)
			CombatEvents.actor_downed.emit(t)

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

func _skill_name(skill: Resource) -> String:
	var maybe_name = skill.get("mnemonic_name")
	if maybe_name != null:
		return maybe_name
	maybe_name = skill.get("display_name")
	if maybe_name != null:
		return maybe_name
	return ""

func _mp_cost(skill: Resource) -> int:
	var maybe_cost = skill.get("mp_cost")
	return maybe_cost if maybe_cost != null else 0

func _hp_cost_percent(skill: Resource) -> float:
	var maybe_cost = skill.get("hp_cost_percent")
	return maybe_cost if maybe_cost != null else 0.0

func _ap_reduction_conditions(skill: Resource) -> Dictionary:
	var maybe_conditions = skill.get("ap_reduction_conditions")
	return maybe_conditions if maybe_conditions != null else {}

func _ap_generation_bonuses(skill: Resource) -> Dictionary:
	var maybe_bonuses = skill.get("ap_generation_bonuses")
	return maybe_bonuses if maybe_bonuses != null else {}
