class_name GridCell
extends Resource

var col: int = 0
var row: int = 0
var height: int = 0       # mechanical tier — combat calculations only (hit bonus/penalty, melee range)
var snap_y: float = 0.0   # visual Y — actual world position the character stands at
var movement_cost: int = 1  # 1 = normal terrain, 2 = difficult terrain
var is_impassable: bool = false
var occupant: Node = null   # typed as CombatCharacter once combat integrates

func world_position(cell_size: float) -> Vector3:
	return Vector3(col * cell_size, snap_y, row * cell_size)

func coords() -> Vector2i:
	return Vector2i(col, row)
