class_name GridManager
extends Node

const BASE_MOVE_CT: int = 25  # CT cost to enter one normal-terrain cell
const MAX_MOVE_HEIGHT_DELTA: int = 1  # height difference that blocks movement

@export var cols: int = 8
@export var rows: int = 8
@export var cell_size: float = 2.0
@export var height_step: float = 1.0

var _cells: Array = []  # Array[Array[GridCell]] indexed [col][row]

signal grid_built

func _ready() -> void:
	call_deferred("build_grid")  # deferred so signal connections in parent are established first

func build_grid() -> void:
	_cells.clear()
	for c in range(cols):
		var column: Array = []
		for r in range(rows):
			var cell := GridCell.new()
			cell.col = c
			cell.row = r
			cell.snap_y = cell.height * height_step  # default — override per-cell for organic terrain
			column.append(cell)
		_cells.append(column)
	Log.info("GridManager: built", cols, "x", rows)
	grid_built.emit()

func get_cell(col: int, row: int) -> GridCell:
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return null
	return _cells[col][row]

func get_neighbors(cell: GridCell, include_occupied: bool = true) -> Array[GridCell]:
	var result: Array[GridCell] = []
	for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var neighbor := get_cell(cell.col + offset.x, cell.row + offset.y)
		if neighbor == null:
			continue
		if neighbor.is_impassable:
			continue
		if abs(height_delta(cell, neighbor)) > MAX_MOVE_HEIGHT_DELTA:
			continue
		if not include_occupied and neighbor.occupant != null:
			continue
		result.append(neighbor)
	return result

func get_move_ct_cost(cell: GridCell) -> int:
	return BASE_MOVE_CT * cell.movement_cost

func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows

func height_delta(from_cell: GridCell, to_cell: GridCell) -> int:
	return to_cell.height - from_cell.height

# --- Occupancy ---

func set_occupant(cell: GridCell, unit: Node) -> void:
	cell.occupant = unit

func clear_occupant(cell: GridCell) -> void:
	cell.occupant = null

func is_available(cell: GridCell) -> bool:
	return not cell.is_impassable and cell.occupant == null

func get_cell_for_unit(unit: Node) -> GridCell:
	for col_arr in _cells:
		for cell: GridCell in col_arr:
			if cell.occupant == unit:
				return cell
	return null

# --- Facing ---

enum Facing { NORTH, EAST, SOUTH, WEST }
enum FacingRelation { BACK, SIDE, FRONT }

static func facing_from_move(from_cell: GridCell, to_cell: GridCell) -> Facing:
	var dc := to_cell.col - from_cell.col
	var dr := to_cell.row - from_cell.row
	if abs(dc) >= abs(dr):
		return Facing.EAST if dc > 0 else Facing.WEST
	return Facing.SOUTH if dr > 0 else Facing.NORTH

static func facing_relation(unit_facing: Facing, from_cell: GridCell, to_cell: GridCell) -> FacingRelation:
	var dc := to_cell.col - from_cell.col
	var dr := to_cell.row - from_cell.row
	match unit_facing:
		Facing.NORTH:
			if dr < 0: return FacingRelation.FRONT
			if dr > 0: return FacingRelation.BACK
		Facing.SOUTH:
			if dr > 0: return FacingRelation.FRONT
			if dr < 0: return FacingRelation.BACK
		Facing.EAST:
			if dc > 0: return FacingRelation.FRONT
			if dc < 0: return FacingRelation.BACK
		Facing.WEST:
			if dc < 0: return FacingRelation.FRONT
			if dc > 0: return FacingRelation.BACK
	return FacingRelation.SIDE

# --- Targeting Shapes ---

enum TargetShape { SINGLE, AREA, CROSS }

func get_cells_in_range(origin: GridCell, range_cells: int, shape: TargetShape, facing: Facing = Facing.SOUTH) -> Array[GridCell]:
	match shape:
		TargetShape.SINGLE, TargetShape.AREA:
			return _targets_radial(origin, range_cells)
		TargetShape.CROSS:
			return _targets_cross(origin, range_cells)
	return []

func _targets_radial(origin: GridCell, range_cells: int) -> Array[GridCell]:
	var result: Array[GridCell] = []
	for c in range(origin.col - range_cells, origin.col + range_cells + 1):
		for r in range(origin.row - range_cells, origin.row + range_cells + 1):
			if c == origin.col and r == origin.row:
				continue
			if abs(c - origin.col) + abs(r - origin.row) <= range_cells:
				var cell := get_cell(c, r)
				if cell:
					result.append(cell)
	return result

func _targets_cross(origin: GridCell, range_cells: int) -> Array[GridCell]:
	var result: Array[GridCell] = []
	for i in range(1, range_cells + 1):
		for offset in [Vector2i(i, 0), Vector2i(-i, 0), Vector2i(0, i), Vector2i(0, -i)]:
			var cell := get_cell(origin.col + offset.x, origin.row + offset.y)
			if cell:
				result.append(cell)
	return result
