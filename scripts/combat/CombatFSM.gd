class_name CombatFSM
extends Node



enum State {
	NONE,
	COMBAT_START,
	TURN_START,
	ACTION_SELECT,
	ACTION_EXECUTION,
	TURN_END,
	COMBAT_END
}

var _state: State = State.NONE
var _actors: Array = []
var _active_actor: CombatCharacter = null
var _pending_target: CombatCharacter = null
var _pending_mnemonic: Resource = null
var _action_pipeline: ActionPipeline = null

func start(actors: Array, pipeline: ActionPipeline) -> void:
	_actors = actors
	_action_pipeline = pipeline
	for actor: CombatCharacter in _actors:
		if actor.ai_behavior != null:
			actor.ai_behavior.setup(_actors)
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
		State.TURN_END:         _enter_turn_end()
		State.COMBAT_END:       _enter_combat_end()

func _enter_combat_start() -> void:
	CombatEvents.combat_started.emit()
	_transition(State.TURN_START)

func _enter_turn_start() -> void:
	_active_actor = TurnTracker.advance_to_next_turn(_actors)
	_active_actor.tokens.tick_turn_start()
	if _active_actor.tokens.consume_if_present("STUN"):
		Log.info("TurnStart — stunned", _active_actor.character_name)
		CombatEvents.turn_started.emit(_active_actor)
		_transition(State.TURN_END)
		return
	Log.info("TurnStart", _active_actor.character_name)
	CombatEvents.turn_started.emit(_active_actor)
	_transition(State.ACTION_SELECT)

func _enter_action_select() -> void:
	CombatEvents.please_select_action.emit(_active_actor)
	# FSM is actor-agnostic. PlayerInputComponent fires action_selected for players,
	# AIBehaviorComponent fires it for enemies. We just wait.
	# Godot 4: awaiting a multi-param signal yields Array [param0, param1].
	# action_selected(mnemonic: Resource, target: CombatCharacter) → result[0], result[1].
	# WAIT or no-target emits (null, null) — null check below catches it.
	var result: Array = await CombatEvents.action_selected
	_pending_mnemonic = result[0]
	_pending_target = result[1] as CombatCharacter
	if _pending_target == null:
		Log.info("ActionSelect — WAIT selected")
		_transition(State.TURN_END)
		return
	Log.info("ActionSelect — target:", _pending_target.character_name)
	_transition(State.ACTION_EXECUTION)

func _enter_action_execution() -> void:
	if _pending_mnemonic == null:
		Log.warn("ActionExecution — no mnemonic, skipping")
		_transition(State.TURN_END)
		return

	_action_pipeline.run(_pending_mnemonic, _active_actor, [_pending_target], _actors)
	await _action_pipeline.pipeline_complete
	_transition(State.TURN_END)

func _enter_turn_end() -> void:
	_active_actor.tokens.tick_turn_end()
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
