class_name GridTestController
extends Node3D

const CELL_COLORS := {
	"normal": Color(0.55, 0.55, 0.55, 0.9),
	"impassable": Color(0.15, 0.15, 0.15),
	"reachable": Color(0.2, 0.8, 0.2, 0.85),
	"selected": Color(1.0, 0.8, 0.0),
	"targeting": Color(1.0, 0.5, 0.0, 0.85),
}

const MOVE_BUDGET: int = 100  # one full CT turn at PULSE 25

@onready var _grid_manager: GridManager = $GridManager

var _cell_visuals: Dictionary = {}   # GridCell -> MeshInstance3D
var _selected_unit: Node3D = null
var _unit_cell: GridCell = null
var _unit_facing: GridManager.Facing = GridManager.Facing.SOUTH
var _reachable: Dictionary = {}      # GridCell -> int (CT cost)

func _ready() -> void:
	_grid_manager.grid_built.connect(_on_grid_built)

func _on_grid_built() -> void:
	_apply_test_layout()
	_build_cell_visuals()
	_spawn_test_unit()

func _apply_test_layout() -> void:
	# height = mechanical tier, snap_y = visual position (set both explicitly here)
	var h1 := _grid_manager.height_step * 1.0
	var h2 := _grid_manager.height_step * 2.0
	_grid_manager.get_cell(3, 3).height = 1; _grid_manager.get_cell(3, 3).snap_y = h1
	_grid_manager.get_cell(4, 3).height = 1; _grid_manager.get_cell(4, 3).snap_y = h1
	_grid_manager.get_cell(4, 4).height = 2; _grid_manager.get_cell(4, 4).snap_y = h2
	_grid_manager.get_cell(5, 2).movement_cost = 2
	_grid_manager.get_cell(5, 3).movement_cost = 2
	_grid_manager.get_cell(2, 2).is_impassable = true
	_grid_manager.get_cell(2, 3).is_impassable = true

func _build_cell_visuals() -> void:
	for visual: Node in _cell_visuals.values():
		visual.queue_free()
	_cell_visuals.clear()

	for c in range(_grid_manager.cols):
		for r in range(_grid_manager.rows):
			var cell := _grid_manager.get_cell(c, r)
			var body := StaticBody3D.new()
			var mesh_inst := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(_grid_manager.cell_size * 0.9, 0.1, _grid_manager.cell_size * 0.9)
			mesh_inst.mesh = box
			var color_key := "impassable" if cell.is_impassable else "normal"
			mesh_inst.set_surface_override_material(0, _make_material(CELL_COLORS[color_key]))
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(_grid_manager.cell_size * 0.9, 0.2, _grid_manager.cell_size * 0.9)
			shape.shape = box_shape
			body.add_child(mesh_inst)
			body.add_child(shape)
			body.position = cell.world_position(_grid_manager.cell_size)
			add_child(body)
			_cell_visuals[cell] = mesh_inst

func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _spawn_test_unit() -> void:
	_selected_unit = Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.3)
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = 0.5
	_selected_unit.add_child(mesh_inst)
	add_child(_selected_unit)

	var start := _grid_manager.get_cell(0, 0)
	_grid_manager.set_occupant(start, _selected_unit)
	_unit_cell = start
	_selected_unit.position = start.world_position(_grid_manager.cell_size)
	Log.info("GridTest: unit spawned at", start.coords())

# --- Input Handling ---

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var clicked := _raycast_to_cell()
	if not clicked:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_on_left_click(clicked)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_on_right_click(clicked)

func _raycast_to_cell() -> GridCell:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var params := PhysicsRayQueryParameters3D.create(origin, origin + direction * 200.0)
	var result := get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return null
	var hit: Vector3 = result.position
	var col := int(round(hit.x / _grid_manager.cell_size))
	var row := int(round(hit.z / _grid_manager.cell_size))
	return _grid_manager.get_cell(col, row)

func _on_left_click(cell: GridCell) -> void:
	if _reachable.has(cell):
		_move_unit_to(cell)
	else:
		_reachable = Pathfinder.get_reachable(_grid_manager, _unit_cell, MOVE_BUDGET)
		_refresh_visuals()
		Log.debug("GridTest: reachable cells", _reachable.size())

func _on_right_click(cell: GridCell) -> void:
	var targets := _grid_manager.get_cells_in_range(cell, 3, GridManager.TargetShape.CROSS)
	for c: GridCell in _cell_visuals:
		var mat := (_cell_visuals[c] as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		if c.is_impassable:
			mat.albedo_color = CELL_COLORS.impassable
		elif targets.has(c):
			mat.albedo_color = CELL_COLORS.targeting
		else:
			mat.albedo_color = CELL_COLORS.normal
	Log.debug("GridTest: cross range 3 from", cell.coords(), "hits", targets.size(), "cells")

func _move_unit_to(target_cell: GridCell) -> void:
	var path := Pathfinder.find_path(_grid_manager, _unit_cell, target_cell)
	if path.is_empty():
		Log.warn("GridTest: no path to", target_cell.coords())
		return

	var ct_spent: int = _reachable[target_cell]
	_unit_facing = GridManager.facing_from_move(_unit_cell, target_cell)

	_grid_manager.clear_occupant(_unit_cell)
	_unit_cell = target_cell
	_grid_manager.set_occupant(_unit_cell, _selected_unit)
	_selected_unit.position = _unit_cell.world_position(_grid_manager.cell_size)

	_reachable.clear()
	_refresh_visuals()

	Log.info("GridTest: moved to", target_cell.coords(),
		"| CT spent:", ct_spent,
		"| facing:", GridManager.Facing.keys()[_unit_facing])

func _refresh_visuals() -> void:
	for cell: GridCell in _cell_visuals:
		var mat := (_cell_visuals[cell] as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		if cell.is_impassable:
			mat.albedo_color = CELL_COLORS.impassable
		elif cell == _unit_cell:
			mat.albedo_color = CELL_COLORS.selected
		elif _reachable.has(cell):
			mat.albedo_color = CELL_COLORS.reachable
		else:
			mat.albedo_color = CELL_COLORS.normal
