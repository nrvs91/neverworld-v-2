class_name SkillPresenter
extends Node

signal impact_triggered

@export var visuals: CombatVisuals

var _data: SkillPresentationData
var _target_pos: Vector3
var _vfx_container: Node3D

@onready var _sfx_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func configure(data: SkillPresentationData, target_pos: Vector3, vfx_container: Node3D) -> void:
	_data = data
	_target_pos = target_pos
	_vfx_container = vfx_container

func spawn_self_vfx() -> void:
	if _data == null or _data.on_self_vfx == null:
		return
	var vfx: Node3D = _data.on_self_vfx.instantiate()
	_vfx_container.add_child(vfx)
	vfx.global_position = visuals.global_position

func spawn_target_vfx() -> void:
	if _data == null or _data.on_target_vfx == null:
		return
	var vfx: Node3D = _data.on_target_vfx.instantiate()
	_vfx_container.add_child(vfx)
	vfx.global_position = _target_pos

func play_cast_sfx() -> void:
	if _data == null or _data.cast_sfx == null:
		return
	_sfx_player.stream = _data.cast_sfx
	_sfx_player.play()

func play_impact_sfx() -> void:
	if _data == null or _data.impact_sfx == null:
		return
	_sfx_player.stream = _data.impact_sfx
	_sfx_player.play()

func start_approach() -> void:
	visuals.approach(_target_pos)

func start_recover() -> void:
	visuals.recover()

func trigger_damage() -> void:
	Log.info("SkillPresenter — impact_triggered")
	impact_triggered.emit()
