class_name TargetingCursor
extends Node3D

signal hover_changed(old_actor: CombatCharacter, new_actor: CombatCharacter)
signal target_confirmed(actor: CombatCharacter)
signal target_cancelled

const CURSOR_HEIGHT: float = 0.6
const PYRAMID_RADIUS: float = 0.15
const PYRAMID_HEIGHT: float = 0.25

var _candidates: Array = []
var _index: int = 0

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.95, 0.82, 0.35)  # AP bar gold
	var mesh_instance := $Marker as MeshInstance3D
	mesh_instance.mesh = _build_pyramid(PYRAMID_RADIUS, PYRAMID_HEIGHT)
	mesh_instance.set_surface_override_material(0, mat)

func _build_pyramid(r: float, h: float) -> ArrayMesh:
	# Equilateral triangle base at y=h, apex at y=0 — points down at the target
	var v0 := Vector3(r, h, 0.0)
	var v1 := Vector3(-r * 0.5, h,  r * 0.866025)
	var v2 := Vector3(-r * 0.5, h, -r * 0.866025)
	var tip := Vector3(0.0, 0.0, 0.0)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()

	_add_face(verts, norms, v0, v2, v1)   # base (normal up)
	_add_face(verts, norms, tip, v1, v0)  # side A
	_add_face(verts, norms, tip, v2, v1)  # side B
	_add_face(verts, norms, tip, v0, v2)  # side C

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_face(verts: PackedVector3Array, norms: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	verts.append_array([a, b, c])
	norms.append_array([n, n, n])

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
