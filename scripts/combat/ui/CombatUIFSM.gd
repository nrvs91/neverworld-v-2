class_name CombatUIFSM
extends Node

enum State { IDLE, WATCHING, PLAYER_MENU, PLAYER_TARGETING, COMBAT_OVER }

const DamageNumberScene = preload("res://scenes/combat/ui/damage_number.tscn")

@onready var enemy_bar: EnemyCardBar = $"../CombatUI/EnemyCardBar"
@onready var player_bar: PlayerCardBar = $"../CombatUI/PlayerCardBar"
@onready var info_panel: InfoPanel = $"../CombatUI/InfoPanel"
@onready var cursor: TargetingCursor = $"../TargetingCursor"

var _state: State = State.IDLE
var _actors: Array = []
var _active_actor: CombatCharacter = null
var _started: bool = false

func start(actors: Array) -> void:
	if _started:
		Log.warn("CombatUIFSM.start() called twice — ignoring")
		return
	_started = true
	_actors = actors
	var players := actors.filter(func(a: CombatCharacter) -> bool: return a.is_player_controlled)
	var enemies := actors.filter(func(a: CombatCharacter) -> bool: return not a.is_player_controlled)
	player_bar.setup(players)
	enemy_bar.setup(enemies)
	player_bar.action_chosen.connect(_on_action_chosen)
	cursor.hover_changed.connect(_on_cursor_hover_changed)
	cursor.target_confirmed.connect(_on_target_confirmed)
	cursor.target_cancelled.connect(_on_target_cancelled)
	CombatEvents.turn_started.connect(_on_turn_started)
	CombatEvents.please_select_action.connect(_on_please_select_action)
	CombatEvents.action_executed.connect(_on_action_executed)
	CombatEvents.actor_downed.connect(_on_actor_downed)
	CombatEvents.combat_ended.connect(_on_combat_ended)
	_transition(State.WATCHING)
	Log.info("CombatUIFSM started")

func _transition(next: State) -> void:
	var msg: String = State.keys()[_state] + " -> " + State.keys()[next]
	Log.info("CombatUIFSM", msg)
	_state = next
	match next:
		State.WATCHING:         _enter_watching()
		State.PLAYER_MENU:      _enter_player_menu()
		State.PLAYER_TARGETING: _enter_player_targeting()
		State.COMBAT_OVER:      _enter_combat_over()

func _enter_watching() -> void:
	player_bar.reset_active()
	cursor.stop()
	info_panel.hide_panel()

func _enter_player_menu() -> void:
	cursor.stop()
	player_bar.set_active(_active_actor)
	info_panel.show_text("A/D: switch menu   W/S: navigate   Enter: confirm")

func _enter_player_targeting() -> void:
	var targets := _actors.filter(func(a: CombatCharacter) -> bool:
		return not a.is_player_controlled and not a.vitals.is_downed()
	)
	cursor.start(targets)
	info_panel.show_text("D/A: cycle target   Enter: confirm   Esc: cancel")

func _enter_combat_over() -> void:
	cursor.stop()
	info_panel.hide_panel()

func _on_turn_started(actor: CombatCharacter) -> void:
	_active_actor = actor
	Log.info("CombatUIFSM — turn", actor.character_name)

func _on_please_select_action(actor: CombatCharacter) -> void:
	_active_actor = actor
	if actor.is_player_controlled:
		_transition(State.PLAYER_MENU)
	else:
		_transition(State.WATCHING)

func _on_action_chosen(category: String, _item_index: int) -> void:
	if category == "WAIT":
		CombatEvents.action_selected.emit(null)
		_transition(State.WATCHING)
		return
	if category == "ACT":
		_transition(State.PLAYER_TARGETING)

func _on_target_confirmed(target: CombatCharacter) -> void:
	CombatEvents.action_selected.emit(target)
	_transition(State.WATCHING)

func _on_target_cancelled() -> void:
	_transition(State.PLAYER_MENU)

func _on_cursor_hover_changed(old_actor: CombatCharacter, new_actor: CombatCharacter) -> void:
	if old_actor:
		if old_actor.is_player_controlled:
			player_bar.nudge_actor(old_actor, false)
		else:
			enemy_bar.nudge_actor(old_actor, false)
	if new_actor:
		if new_actor.is_player_controlled:
			player_bar.nudge_actor(new_actor, true)
		else:
			enemy_bar.nudge_actor(new_actor, true)

func _on_action_executed(actor: CombatCharacter, target: CombatCharacter, damage: int) -> void:
	# Currently fire-and-forget — spawns the damage number and moves on.
	# When skill animations arrive, this becomes the ANIMATING state entry point:
	# play actor's attack anim + VFX, await completion, then spawn the damage number,
	# then emit presentation_finished to unblock CombatFSM. See Option A note in CombatFSM.
	var dn := DamageNumberScene.instantiate() as DamageNumber
	get_parent().add_child(dn)
	dn.animation_finished.connect(_on_damage_number_done.bind(target))
	dn.show_at(target.global_position + Vector3(0.0, 0.5, 0.0), damage)

func _on_damage_number_done(target: CombatCharacter) -> void:
	if target.is_player_controlled:
		player_bar.refresh_actor(target)
	else:
		enemy_bar.refresh_actor(target)

func _on_actor_downed(actor: CombatCharacter) -> void:
	if actor.is_player_controlled:
		player_bar.set_actor_inactive(actor)
	else:
		enemy_bar.remove_actor(actor)
	Log.info("CombatUIFSM — downed", actor.character_name)

func _on_combat_ended(_player_won: bool) -> void:
	_transition(State.COMBAT_OVER)

func _unhandled_input(event: InputEvent) -> void:
	match _state:
		State.PLAYER_MENU:      _handle_menu_input(event)
		State.PLAYER_TARGETING: _handle_targeting_input(event)

func _handle_menu_input(event: InputEvent) -> void:
	var menu := player_bar.get_active_menu()
	if menu == null:
		return
	if event.is_action_pressed("combat_prev"):
		menu.prev_category()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_next"):
		menu.next_category()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_up"):
		menu.prev_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_down"):
		menu.next_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_confirm"):
		menu.confirm()
		get_viewport().set_input_as_handled()

func _handle_targeting_input(event: InputEvent) -> void:
	if event.is_action_pressed("combat_next") or event.is_action_pressed("combat_down"):
		cursor.next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_prev") or event.is_action_pressed("combat_up"):
		cursor.prev()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_confirm"):
		cursor.confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("combat_cancel"):
		cursor.cancel()
		get_viewport().set_input_as_handled()
