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
