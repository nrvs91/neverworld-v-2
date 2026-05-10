class_name CombatFSM
extends Node

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
	# NOTE: suspends via await — _transition() is not re-entrant while this state is active.
	# Replace with `await CombatEvents.action_selected` when UI FSM is built.
	CombatEvents.please_select_action.emit(_active_actor)
	await get_tree().create_timer(0.4).timeout
	
	_pending_target = _first_living_opponent(_active_actor)
	if _pending_target == null:
		Log.warn("ActionSelect — no living opponent found, skipping to TurnEnd")
		_transition(State.TURN_END)
		return
	
	Log.info("ActionSelect", _active_actor.character_name)
	Log.info("target ->", _pending_target.character_name)
	CombatEvents.action_selected.emit(null, _pending_target)
	_transition(State.ACTION_EXECUTION)

func _enter_action_execution() -> void:
	var damage: int = CombatCalculator.base_attack(_active_actor, _pending_target)
	_pending_target.vitals.take_damage(damage)
	Log.info("ActionExecution", _active_actor.character_name)
	Log.info("hits", _pending_target.character_name)
	Log.info("for", damage)
	CombatEvents.action_executed.emit(_active_actor, _pending_target, damage)
	
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
