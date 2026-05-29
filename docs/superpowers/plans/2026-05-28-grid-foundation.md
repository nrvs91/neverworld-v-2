# Grid Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully isolated tactical grid system on a clean branch — cells, A* pathfinding, height, facing, and spatial targeting shapes — proved in a standalone test scene with zero combat code dependencies.

**Architecture:** `GridCell` is a plain Resource (data only). `GridManager` is a Node that owns the cell array and answers all spatial queries. `Pathfinder` is a static utility with no node base. `GridTestController` drives an isolated test scene. Zero imports from existing combat scripts. When the grid is proven, Plan 2 bends the combat code to fit.

**Tech Stack:** Godot 4.6, GDScript

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `scripts/grid/GridCell.gd` | Create | Cell data resource — col, row, height, movement_cost, occupant |
| `scripts/grid/GridManager.gd` | Create | Grid construction, neighbor queries, occupancy, facing, targeting shapes |
| `scripts/grid/Pathfinder.gd` | Create | A* `find_path()` and Dijkstra `get_reachable()` |
| `scripts/grid/GridTestController.gd` | Create | Drives test scene — visualization, input, movement |
| `scenes/grid/grid_test.tscn` | Create | Isolated sandbox — not connected to boot.tscn |

---

### Task 1: Create Branch and Folder Structure

**Files:**
- Create: `scripts/grid/` (folder)
- Create: `scenes/grid/` (folder)

- [ ] **Step 1: Create the git branch**

```bash
git checkout -b tactical-grid
```

- [ ] **Step 2: Create the folders**

```bash
mkdir -p /home/bart/Projects/neverworld-v-2/scripts/grid
mkdir -p /home/bart/Projects/neverworld-v-2/scenes/grid
```

- [ ] **Step 3: Commit**

```bash
touch /home/bart/Projects/neverworld-v-2/scripts/grid/.gitkeep
touch /home/bart/Projects/neverworld-v-2/scenes/grid/.gitkeep
git add scripts/grid/.gitkeep scenes/grid/.gitkeep
git commit -m "feat: scaffold grid foundation branch"
```

---

### Task 2: GridCell Resource

**Files:**
- Create: `scripts/grid/GridCell.gd`

- [ ] **Step 1: Write GridCell**

`scripts/grid/GridCell.gd`:
```gdscript
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/grid/GridCell.gd
git commit -m "feat: GridCell resource with position and terrain data"
```

---

### Task 3: GridManager — Construction and Neighbor Queries

**Files:**
- Create: `scripts/grid/GridManager.gd`

- [ ] **Step 1: Write GridManager**

`scripts/grid/GridManager.gd`:
```gdscript
class_name GridManager
extends Node

const BASE_MOVE_CT: int = 25  # CT cost to enter one normal-terrain cell

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

func get_neighbors(cell: GridCell) -> Array[GridCell]:
	var result: Array[GridCell] = []
	for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var neighbor := get_cell(cell.col + offset.x, cell.row + offset.y)
		if neighbor != null and not neighbor.is_impassable:
			result.append(neighbor)
	return result

func get_move_ct_cost(cell: GridCell) -> int:
	return BASE_MOVE_CT * cell.movement_cost

func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows
```

- [ ] **Step 2: Commit**

```bash
git add scripts/grid/GridManager.gd
git commit -m "feat: GridManager grid construction and neighbor queries"
```

---

### Task 4: GridManager — Occupancy, Height Queries, and Facing

**Files:**
- Modify: `scripts/grid/GridManager.gd`

- [ ] **Step 1: Add enums, occupancy, height, and facing methods**

Append to `GridManager.gd` (inside the class body, after `in_bounds()`):
```gdscript
enum Facing { NORTH, EAST, SOUTH, WEST }
enum FacingRelation { BACK, SIDE, FRONT }

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

func height_delta(from_cell: GridCell, to_cell: GridCell) -> int:
	return to_cell.height - from_cell.height

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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/grid/GridManager.gd
git commit -m "feat: GridManager occupancy, height delta, and facing queries"
```

---

### Task 5: Pathfinder — find_path()

**Files:**
- Create: `scripts/grid/Pathfinder.gd`

- [ ] **Step 1: Write Pathfinder with A***

`scripts/grid/Pathfinder.gd`:
```gdscript
class_name Pathfinder
extends RefCounted

# Returns Array[GridCell] from start to goal inclusive.
# Empty array if no path exists. Cost unit is CT.
static func find_path(grid: GridManager, start: GridCell, goal: GridCell) -> Array[GridCell]:
	if start == goal:
		return [start]
	if goal.is_impassable:
		return []

	var open_set: Array[GridCell] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}

	while not open_set.is_empty():
		var current: GridCell = _cheapest(open_set, g_score, goal)
		if current == goal:
			return _build_path(came_from, current)

		open_set.erase(current)

		for neighbor: GridCell in grid.get_neighbors(current):
			var tentative_g: int = g_score[current] + grid.get_move_ct_cost(neighbor)
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return []

static func _cheapest(open_set: Array[GridCell], g_score: Dictionary, goal: GridCell) -> GridCell:
	var best: GridCell = open_set[0]
	var best_f: int = g_score.get(best, 0) + _heuristic(best, goal)
	for cell: GridCell in open_set:
		var f: int = g_score.get(cell, 0) + _heuristic(cell, goal)
		if f < best_f:
			best = cell
			best_f = f
	return best

static func _heuristic(cell: GridCell, goal: GridCell) -> int:
	return (abs(cell.col - goal.col) + abs(cell.row - goal.row)) * GridManager.BASE_MOVE_CT

static func _build_path(came_from: Dictionary, current: GridCell) -> Array[GridCell]:
	var path: Array[GridCell] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path
```

- [ ] **Step 2: Commit**

```bash
git add scripts/grid/Pathfinder.gd
git commit -m "feat: Pathfinder A* find_path with CT cost weighting"
```

---

### Task 6: Pathfinder — get_reachable()

**Files:**
- Modify: `scripts/grid/Pathfinder.gd`

- [ ] **Step 1: Add get_reachable() to Pathfinder**

Append inside the `Pathfinder` class in `Pathfinder.gd`, after `_build_path()`:
```gdscript
# Returns Dictionary of {GridCell: int} — cells reachable within budget
# mapped to their CT cost to reach. Start cell is not included.
static func get_reachable(grid: GridManager, start: GridCell, budget: int) -> Dictionary:
	var costs: Dictionary = {start: 0}
	var visited: Dictionary = {}
	var frontier: Array = [{"cell": start, "cost": 0}]

	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a.cost < b.cost)
		var entry: Dictionary = frontier.pop_front()
		var current: GridCell = entry.cell

		if visited.has(current):
			continue
		visited[current] = true

		for neighbor: GridCell in grid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			var new_cost: int = entry.cost + grid.get_move_ct_cost(neighbor)
			if new_cost <= budget and new_cost < costs.get(neighbor, budget + 1):
				costs[neighbor] = new_cost
				frontier.append({"cell": neighbor, "cost": new_cost})

	costs.erase(start)
	return costs
```

- [ ] **Step 2: Commit**

```bash
git add scripts/grid/Pathfinder.gd
git commit -m "feat: Pathfinder Dijkstra get_reachable within CT budget"
```

---

### Task 7: Test Scene — Setup and Grid Visualization

**Files:**
- Create: `scenes/grid/grid_test.tscn`
- Create: `scripts/grid/GridTestController.gd` (partial — setup only this task)

- [ ] **Step 1: Create the test scene in the Godot editor**

1. Scene → New Scene → Root: Node3D → rename to `GridTest`
2. Save as `scenes/grid/grid_test.tscn`
3. Add child Node3D named `GridManager` → attach `scripts/grid/GridManager.gd`
4. Add child DirectionalLight3D → position `Vector3(5, 10, 5)`, rotate to point roughly downward
5. Add child Camera3D → set `Projection = Orthogonal`, `Size = 20` → position `Vector3(8, 14, 14)`, look toward grid center

Do NOT connect boot.tscn to this scene. Run it directly via right-click → Run This Scene.

- [ ] **Step 2: Write GridTestController — setup and visualization**

`scripts/grid/GridTestController.gd`:
```gdscript
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
```

- [ ] **Step 3: Attach GridTestController to the GridTest root node in the editor**

Select the GridTest root node → attach `scripts/grid/GridTestController.gd`.

- [ ] **Step 4: Run the scene**

Right-click `scenes/grid/grid_test.tscn` → Run This Scene.

Expected: 8×8 grid of grey boxes. Cells (2,2) and (2,3) are dark/impassable. Cells (3,3) and (4,3) are elevated (height 1), (4,4) is higher (height 2). Red sphere at (0,0). No errors in Godot console.

- [ ] **Step 5: Commit**

```bash
git add scenes/grid/grid_test.tscn scripts/grid/GridTestController.gd
git commit -m "feat: grid test scene with cell visualization and test unit"
```

---

### Task 8: GridTestController — Selection and Reachability Display

**Files:**
- Modify: `scripts/grid/GridTestController.gd`

- [ ] **Step 1: Add input handling, reachability display, and movement stub**

Append to `GridTestController.gd` (inside the class, after `_spawn_test_unit()`):
```gdscript
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

func _on_right_click(_cell: GridCell) -> void:
	pass  # targeting display added in Task 10

func _move_unit_to(_target: GridCell) -> void:
	Log.debug("GridTest: _move_unit_to — implemented in next task")

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
```

- [ ] **Step 2: Run the scene**

Right-click `scenes/grid/grid_test.tscn` → Run This Scene.

Expected: Left-click anywhere → green cells highlight showing reachable range from (0,0). Impassable cells stay dark. Elevated cells are reachable. Log shows reachable count (~20+ cells for budget 100).

- [ ] **Step 3: Commit**

```bash
git add scripts/grid/GridTestController.gd
git commit -m "feat: reachability display from unit position"
```

---

### Task 9: GridTestController — Movement and Facing

**Files:**
- Modify: `scripts/grid/GridTestController.gd`

- [ ] **Step 1: Replace the _move_unit_to() stub with the real implementation**

In `GridTestController.gd`, replace:
```gdscript
func _move_unit_to(_target: GridCell) -> void:
	Log.debug("GridTest: _move_unit_to — implemented in next task")
```

With:
```gdscript
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
```

- [ ] **Step 2: Run the scene**

Right-click `scenes/grid/grid_test.tscn` → Run This Scene.

Expected:
1. Left-click → green reachable cells appear
2. Left-click a green cell → unit moves there, snaps to correct Y height, visuals reset
3. Moving to elevated cells (3,3), (4,3), (4,4) shows unit at correct height
4. Log output shows `CT spent: 25` for adjacent cell, `CT spent: 50` for difficult terrain cell, and facing direction

- [ ] **Step 3: Commit**

```bash
git add scripts/grid/GridTestController.gd
git commit -m "feat: unit movement with CT cost tracking and facing update"
```

---

### Task 10: Spatial Targeting Shapes

**Files:**
- Modify: `scripts/grid/GridManager.gd`
- Modify: `scripts/grid/GridTestController.gd`

- [ ] **Step 1: Add targeting enum and shape queries to GridManager**

Append inside the `GridManager` class after the `facing_relation()` method:
```gdscript
enum TargetShape { SINGLE, AREA, CROSS, LINE, CONE }

func get_cells_in_range(origin: GridCell, range_cells: int, shape: TargetShape, facing: Facing) -> Array[GridCell]:
	match shape:
		TargetShape.SINGLE, TargetShape.AREA:
			return _targets_radial(origin, range_cells)
		TargetShape.CROSS:
			return _targets_cross(origin, range_cells)
		TargetShape.LINE:
			return _targets_line(origin, range_cells, facing)
		TargetShape.CONE:
			return _targets_cone(origin, range_cells, facing)
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

func _targets_line(origin: GridCell, range_cells: int, facing: Facing) -> Array[GridCell]:
	var result: Array[GridCell] = []
	var dir := _facing_to_vec(facing)
	for i in range(1, range_cells + 1):
		var cell := get_cell(origin.col + dir.x * i, origin.row + dir.y * i)
		if cell:
			result.append(cell)
	return result

func _targets_cone(origin: GridCell, range_cells: int, facing: Facing) -> Array[GridCell]:
	var result: Array[GridCell] = []
	var fwd := _facing_to_vec(facing)
	var side := Vector2i(abs(fwd.y), abs(fwd.x))  # perpendicular axis
	for i in range(1, range_cells + 1):
		for spread in range(-i, i + 1):
			var c := origin.col + fwd.x * i + side.x * spread
			var r := origin.row + fwd.y * i + side.y * spread
			var cell := get_cell(c, r)
			if cell and not result.has(cell):
				result.append(cell)
	return result

static func _facing_to_vec(facing: Facing) -> Vector2i:
	match facing:
		Facing.NORTH: return Vector2i(0, -1)
		Facing.SOUTH: return Vector2i(0, 1)
		Facing.EAST:  return Vector2i(1, 0)
		Facing.WEST:  return Vector2i(-1, 0)
	return Vector2i(0, 1)
```

- [ ] **Step 2: Wire right-click targeting display in GridTestController**

In `GridTestController.gd`, replace:
```gdscript
func _on_right_click(_cell: GridCell) -> void:
	pass  # targeting display added in Task 10
```

With:
```gdscript
func _on_right_click(cell: GridCell) -> void:
	var targets := _grid_manager.get_cells_in_range(cell, 3, GridManager.TargetShape.CONE, _unit_facing)
	for c: GridCell in _cell_visuals:
		var mat := (_cell_visuals[c] as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		if c.is_impassable:
			mat.albedo_color = CELL_COLORS.impassable
		elif targets.has(c):
			mat.albedo_color = CELL_COLORS.targeting
		else:
			mat.albedo_color = CELL_COLORS.normal
	Log.debug("GridTest: cone range 3 from", cell.coords(), "hits", targets.size(), "cells | unit facing:", GridManager.Facing.keys()[_unit_facing])
```

- [ ] **Step 3: Run the scene**

Right-click `scenes/grid/grid_test.tscn` → Run This Scene.

Expected:
1. Left-click → green reachable range, click green cell to move
2. After moving, right-click any cell → orange cone pattern projects from that cell in the direction the unit is currently facing
3. Move unit in a different direction (facing updates), right-click again → cone rotates accordingly
4. Log shows cell count and facing direction

- [ ] **Step 4: Commit**

```bash
git add scripts/grid/GridManager.gd scripts/grid/GridTestController.gd
git commit -m "feat: spatial targeting shapes — SINGLE, AREA, CROSS, LINE, CONE"
```

---

## Milestone: Grid Phase Complete

The grid phase is done when all of the following hold in the running test scene:

- [ ] 8×8 grid renders in 3D with elevated cells at correct Y positions
- [ ] Impassable cells are visually distinct and block movement
- [ ] Left-click shows green reachable cells within CT budget from unit position
- [ ] Clicking a green cell moves the unit there — Log confirms CT spent and facing
- [ ] Difficult terrain cells (movement_cost = 2) cost double CT — verify in Log
- [ ] Unit at elevated cell snaps to correct Y height
- [ ] Right-click shows orange cone targeting from that cell based on unit's current facing
- [ ] Moving unit in different directions changes the cone orientation on right-click

When this milestone is reached, move to Plan 2: Combat Integration — bending `ActionContext`, `CombatCharacter`, `TurnTracker`, and `CombatCalculator` to the grid.
