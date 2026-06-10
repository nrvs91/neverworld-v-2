class_name AIBehaviorComponent
extends Node

# Preload required — 'A' resolves before 'C' alphabetically in Godot's class_name parser.
const CombatCharacterClass = preload("res://scripts/combat/CombatCharacter.gd")

const DECISION_DELAY: float = 0.6

var _all_actors: Array = []

func setup(actors: Array) -> void:
	_all_actors = actors

func _ready() -> void:
	CombatEvents.please_select_action.connect(_on_please_select_action)

func _exit_tree() -> void:
	CombatEvents.please_select_action.disconnect(_on_please_select_action)

func _on_please_select_action(actor: CombatCharacterClass) -> void:
	if actor != get_parent():
		return
	_decide()

func _decide() -> void:
	await get_tree().create_timer(DECISION_DELAY).timeout
	var owner_actor := get_parent() as CombatCharacterClass
	var target := _first_living_opponent(owner_actor)
	if target == null:
		Log.info("AIBehaviorComponent — no valid target", owner_actor.character_name)
		CombatEvents.action_selected.emit(null, null)
		return
	var skill = owner_actor.enemy_skills[0] if not owner_actor.enemy_skills.is_empty() else null
	Log.info("AIBehaviorComponent — acting", owner_actor.character_name)
	CombatEvents.action_selected.emit(skill, target)

func _first_living_opponent(actor: CombatCharacterClass) -> CombatCharacterClass:
	for a in _all_actors:
		var cc := a as CombatCharacterClass
		if cc == null or cc.vitals.is_downed():
			continue
		if cc.is_player_controlled != actor.is_player_controlled:
			return cc
	return null
