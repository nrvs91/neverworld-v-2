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
