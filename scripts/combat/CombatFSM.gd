class_name CombatFSM
extends Node

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

enum State {
	NONE,
	COMBAT_START,
	TURN_START,
	ACTION_SELECT,
	ACTION_EXECUTION,
	REACTION_SCAN,
	TURN_END,
	COMBAT_END
}

var _state: State = State.NONE
var _actors: Array = []
var _active_actor: CombatCharacter = null
var _pending_target: CombatCharacter = null
var _pending_mnemonic: MnemonicRes = null

func start(actors: Array) -> void:
	_actors = actors
	Log.info("CombatFSM starting with", _actors.size())
	_transition(State.COMBAT_START)

func _transition(next: State) -> void:
	var msg: String = State.keys()[_state] + " -> " + State.keys()[next]
	Log.info("CombatFSM", msg)
	_state = next
	match next:
		State.COMBAT_START:     _enter_combat_start()
		State.TURN_START:       _enter_turn_start()
		State.ACTION_SELECT:    _enter_action_select()
		State.ACTION_EXECUTION: _enter_action_execution()
		State.REACTION_SCAN:    _enter_reaction_scan()
		State.TURN_END:         _enter_turn_end()
		State.COMBAT_END:       _enter_combat_end()

func _enter_combat_start() -> void:
	CombatEvents.combat_started.emit()
	_transition(State.TURN_START)

func _enter_turn_start() -> void:
	_active_actor = TurnTracker.advance_to_next_turn(_actors)
	# AP gain happens BEFORE token ticks — tokens may modify AP gain
	_active_actor.vitals.gain_ap(1)
	# Token tick order matters (DoT before HoT? Buffs before Debuffs?) — define when token system is built
	_active_actor.tokens.tick_turn_start()
	Log.info("TurnStart", _active_actor.character_name)
	Log.info("AP:", _active_actor.vitals.cur_ap)
	CombatEvents.turn_started.emit(_active_actor)
	_transition(State.ACTION_SELECT)

func _enter_action_select() -> void:
	CombatEvents.please_select_action.emit(_active_actor)

	if not _active_actor.is_player_controlled:
		_pending_target = _first_living_opponent(_active_actor)
		if _pending_target == null:
			Log.info("ActionSelect — enemy has no valid target, skipping")
			_transition(State.TURN_END)
			return
		_pending_mnemonic = _active_actor.mnemonics[0] if not _active_actor.mnemonics.is_empty() else null
		Log.info("ActionSelect — enemy auto:", _pending_target.character_name)
		_transition(State.ACTION_EXECUTION)
		return

	var result: Array = await CombatEvents.action_selected
	_pending_mnemonic = result[0] as MnemonicRes
	_pending_target = result[1] as CombatCharacter
	if _pending_target == null:
		Log.info("ActionSelect — WAIT selected")
		_transition(State.TURN_END)
		return
	Log.info("ActionSelect — target:", _pending_target.character_name)
	_transition(State.ACTION_EXECUTION)

func _enter_action_execution() -> void:
	if _pending_mnemonic == null:
		Log.warn("ActionExecution — no mnemonic, skipping to REACTION_SCAN")
		_transition(State.REACTION_SCAN)
		return

	# Guard: check both costs before spending either — avoids partial deductions
	if _active_actor.vitals.cur_ap < _pending_mnemonic.ap_cost \
			or _active_actor.vitals.cur_mp < _pending_mnemonic.mp_cost:
		Log.warn("ActionExecution — insufficient AP/MP, skipping skill")
		_transition(State.REACTION_SCAN)
		return

	_active_actor.vitals.spend_ap(_pending_mnemonic.ap_cost)
	_active_actor.vitals.spend_mp(_pending_mnemonic.mp_cost)

	var context: ActionContext = SkillExecutor.execute(_pending_mnemonic, _active_actor, _pending_target)

	if _pending_mnemonic.hp_cost_percent > 0.0:
		_active_actor.vitals.spend_hp_percent(_pending_mnemonic.hp_cost_percent)

	for result: Dictionary in context.step_results:
		# Apply damage BEFORE emitting — listeners read post-damage vitals
		if result.hit:
			_pending_target.vitals.take_damage(result.damage)
			CombatEvents.action_executed.emit(_active_actor, _pending_target, result.damage)
		else:
			CombatEvents.combat_text_shown.emit(_pending_target, "MISS")

	Log.info("ActionExecution", "%s->%s total:%d" % [_active_actor.character_name, _pending_target.character_name, context.total_damage])

	if _pending_target.vitals.is_downed():
		Log.info("actor downed", _pending_target.character_name)
		CombatEvents.actor_downed.emit(_pending_target)

	if _check_combat_end():
		return
	_transition(State.REACTION_SCAN)

func _enter_reaction_scan() -> void:
	# STUB: reactions not yet implemented
	if _check_combat_end():
		return
	_transition(State.TURN_END)

func _enter_turn_end() -> void:
	TurnTracker.consume_ct(_active_actor)
	CombatEvents.turn_ended.emit(_active_actor)
	
	if _check_combat_end():
		return
	_transition(State.TURN_START)

func _enter_combat_end() -> void:
	var any_player_alive: bool = false
	
	for a: CombatCharacter in _actors:
		if a.is_player_controlled and not a.vitals.is_downed():
			any_player_alive = true
			break
	
	Log.info("CombatEnd — player_won:", any_player_alive)
	CombatEvents.combat_ended.emit(any_player_alive)

func _check_combat_end() -> bool:
	var any_enemy_alive: bool = false
	var any_player_alive: bool = false
	
	for a: CombatCharacter in _actors:
		if a.vitals.is_downed():
			continue
		
		if a.is_player_controlled:
			any_player_alive = true
		else:
			any_enemy_alive = true
	
	if not any_enemy_alive:
		_transition(State.COMBAT_END)
		return true
	
	if not any_player_alive:
		_transition(State.COMBAT_END)
		return true
	
	return false

func _first_living_opponent(actor: CombatCharacter) -> CombatCharacter:
	for a: CombatCharacter in _actors:
		if a.vitals.is_downed():
			continue
		
		var is_enemy: bool = a.is_player_controlled != actor.is_player_controlled
		if is_enemy:
			return a
	
	return null
