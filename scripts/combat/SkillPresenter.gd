class_name SkillPresenter
extends Node

signal impact_triggered

var _data: SkillPresentationData = null
var _context: ActionContext = null
var _target_pos: Vector3 = Vector3.ZERO
var _vfx_container: Node3D = null

func configure(data: SkillPresentationData, context: ActionContext, target_pos: Vector3, vfx_container: Node3D) -> void:
	_data = data
	_context = context
	_target_pos = target_pos
	_vfx_container = vfx_container

func on_windup() -> void:
	if _data == null:
		return
	if _data.cast_sfx != null:
		var player := AudioStreamPlayer.new()
		player.stream = _data.cast_sfx
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	if _data.on_self_vfx != null:
		if _vfx_container == null:
			Log.error("SkillPresenter.on_windup — _vfx_container is null, cannot spawn self VFX")
			return
		var vfx := _data.on_self_vfx.instantiate() as Node3D
		if vfx != null:
			_vfx_container.add_child(vfx)
			vfx.global_position = _context.source.global_position

func on_dash() -> void:
	if _context != null and _context.source != null:
		_context.source.visuals.approach(_target_pos)

func on_impact() -> void:
	if _data == null:
		impact_triggered.emit()
		return
	if _data.impact_sfx != null:
		var player := AudioStreamPlayer.new()
		player.stream = _data.impact_sfx
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	if _data.on_target_vfx != null:
		if _vfx_container == null:
			Log.error("SkillPresenter.on_impact — _vfx_container is null, cannot spawn target VFX")
			impact_triggered.emit()
			return
		var vfx := _data.on_target_vfx.instantiate() as Node3D
		if vfx != null:
			_vfx_container.add_child(vfx)
			vfx.global_position = _target_pos
	impact_triggered.emit()

func on_recover() -> void:
	if _context != null and _context.source != null:
		_context.source.visuals.recover()
