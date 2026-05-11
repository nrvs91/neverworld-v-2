class_name TargetingCursor
extends Node3D

signal hover_changed(old_actor: CombatCharacter, new_actor: CombatCharacter)
signal target_confirmed(actor: CombatCharacter)
signal target_cancelled

const CURSOR_HEIGHT: float = 0.6

var _candidates: Array = []
var _index: int = 0

func start(candidates: Array) -> void:
	_candidates = candidates
	_index = 0
	visible = true
	if not _candidates.is_empty():
		_update_position()
		hover_changed.emit(null, _current())
	Log.info("TargetingCursor started, candidates:", _candidates.size())

func stop() -> void:
	visible = false
	_candidates = []
	Log.info("TargetingCursor stopped")

func next() -> void:
	if _candidates.is_empty():
		return
	var old := _current()
	_index = (_index + 1) % _candidates.size()
	hover_changed.emit(old, _current())
	_update_position()

func prev() -> void:
	if _candidates.is_empty():
		return
	var old := _current()
	_index = (_index - 1 + _candidates.size()) % _candidates.size()
	hover_changed.emit(old, _current())
	_update_position()

func confirm() -> void:
	if _candidates.is_empty():
		return
	var actor := _current()
	hover_changed.emit(actor, null)
	Log.info("TargetingCursor confirmed", actor.character_name)
	target_confirmed.emit(actor)

func cancel() -> void:
	if not _candidates.is_empty():
		hover_changed.emit(_current(), null)
	Log.info("TargetingCursor cancelled")
	target_cancelled.emit()

func _current() -> CombatCharacter:
	return _candidates[_index]

func _update_position() -> void:
	if _candidates.is_empty():
		return
	global_position = _current().global_position + Vector3(0.0, CURSOR_HEIGHT, 0.0)
