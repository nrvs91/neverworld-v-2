# NEVERWORLD — Tactical Pivot Design Spec
**Date:** 2026-05-28
**Status:** Approved

---

## Why This Pivot

The classical JRPG format — overworld traversal, towns with schedules, dungeons to populate — has insurmountable content requirements for a solo developer. The combat system, mnemonic design, and setting are strong. The asset pipeline was going to kill the project.

The tactical grid format eliminates the uncontrollable content requirements while keeping everything that makes NEVERWORLD interesting: the CT/PULSE turn engine, the mnemonic system, the token architecture, the Baltic post-singularity setting. The format also suits the aesthetic vision — the t3ssl8r-style 3D isometric presentation with 2D sprite characters is exactly what FFT and Tactics Ogre did. It isn't a compromise; it's the right vehicle.

---

## Game Structure

### World Map
A node-based map in the style of Breath of Fire IV. POIs connected by directional routes. Movement is discrete — select a direction to traverse the corresponding route from the current POI to the connected one. No collision, no traversal system, no random encounters. The map is a menu with a painting behind it.

The world map is freely accessible between battles. Roster management, loadout changes, and shop access are always available from the map without requiring a town visit.

**POI Types:**
- **Town** — shops, full HP/MP restore, story scenes
- **Battle** — single authored grid fight
- **Dungeon** — 2–3 sequential grid battles, partial rest at intermission, boss at the end

**Future / Parked:** Camp feature — a simple space where you can walk and talk with party members. Bonus feature, not part of initial scope.

### Between Battles
HP and MP reset after every standalone battle. Inside a dungeon POI, they persist across all sequential fights in that sequence — arrive at the boss in bad shape and you feel it. Dungeon intermissions offer partial restoration. Towns offer full restoration.

### Pre-Battle Deployment
One integrated screen. The full board is visible and navigable. Enemies are on the map and inspectable. Colored spawn cells mark valid deployment positions. The player places their units, reviews the situation, adjusts their mnemonic loadout (see below), and confirms. Deployment IS the pre-battle screen.

### Battle Objectives
Front Mission-style varied objectives per map. Kill-all is the most common but does not carry the whole game.

Supported objective types:
- Defeat all enemies
- Reach extraction point in X turns
- Survive X turns
- Destroy target object(s)
- Escort unit
- Protect unit
- Wave battles (successive enemy waves)

Loss conditions change with the objective. Fail the objective condition → battle lost, not just party wipe.

---

## The Grid

### Two Layers
The grid is two layers. The **presentation layer** is the 3D isometric world — terrain, geometry, the t3ssl8r aesthetic (low-poly, toon shader with assignable step colors, transparent quads sampling floor color for pixel-art vibe). The **logic layer** is a flat 2D grid of cells that sits underneath it, carrying all mechanical meaning. The two layers communicate only through cell world positions — the logic layer tells the presentation where characters stand, nothing else.

### Cell Data
```gdscript
class_name GridCell
extends Resource

var col: int
var row: int
var height: int = 0       # mechanical tier — combat calculations only (hit bonus/penalty, melee range)
var snap_y: float = 0.0   # visual Y — actual world position the character stands at
var movement_cost: int = 1  # 1 = normal, 2 = difficult terrain
var is_impassable: bool = false
var occupant: Node = null

func world_position(cell_size: float) -> Vector3:
    return Vector3(col * cell_size, snap_y, row * cell_size)
```

`height` and `snap_y` are intentionally separate. `height` is a discrete integer tier (0, 1, 2) used only for combat calculations — hit bonuses, penalties, melee range checks. `snap_y` is the float Y coordinate the character actually stands at, authored to match the visual mesh. By default `snap_y` is initialized to `height * height_step` by GridManager, but can be overridden per-cell for organic terrain.

This means the 3D mesh is entirely independent. Sculpt whatever geometry you want in Blender, import it, then author the grid on top: set `height` tiers for mechanical meaning, nudge `snap_y` per cell until characters look right against the actual surface. The two are never coupled.

No per-tile stat bonuses. The grid carries position, not personality. Terrain costs 1× or 2× movement CT to enter. That's the full vocabulary.

### Height Mechanics
Height difference between attacker and target cells carries mechanical weight:
- Attacking **uphill**: hit penalty
- Attacking **downhill**: hit bonus
- Ranged mnemonics firing **downhill**: bonus range
- Large height gap: melee attack impossible

Maps are authored with the principle of "furthest from camera = highest elevation" to preserve readability without camera rotation.

### Facing
Units have a facing direction (four cardinal directions).
- Being attacked automatically rotates the unit toward the attacker
- Manual facing change costs 10 CT (minimum spend, see Turn System)
- **Front:** hit penalty for the attacker
- **Side:** neutral
- **Back:** hit bonus for the attacker

### Camera
Fixed isometric angle. No camera rotation in initial scope — treat rotation as a stretch goal after maps are authored and tested. When geometry occludes a unit, a silhouette shader renders their outline through the occluder so they are always readable.

### Movement Costs Summary
| Action | CT Cost |
|---|---|
| Move 1 tile (normal terrain) | 25 |
| Move 1 tile (difficult terrain) | 50 |
| Facing change | 10 |
| Item use | 25 |
| Mnemonic | Authored per skill |

---

## Combat & Turn System

### CT as Clock and Budget
CT governs both when you act and how much you do when you act. There is no separate AP resource.

**As a clock:** Every actor accumulates CT equal to their PULSE stat after each other actor's turn resolves. First to reach 100 acts. Tiebreaker: higher PULSE goes first. Downed actors do not tick.

**As a budget:** When you act, you do not reset to zero. You spend CT on actions from your current total. Whatever remains is your head start on the next cycle. Expensive turns delay recovery. Efficient turns keep you in the fight.

### The Strategic Question
Every turn asks: *how much CT do I spend right now?*

- Use Uskrav (50 CT) → 50 CT remaining → back in 2 other actor turns
- Use Uskrav twice (100 CT) → 0 CT remaining → back in 4 turns
- Move 4 tiles (100 CT) → 0 CT remaining → back in 4 turns
- Move 1 tile + Uskrav (75 CT) → 25 CT remaining → back in 3 turns

### PULSE
PULSE determines how often you act (CT accumulation rate) and how efficiently expensive actions fit into your rhythm. High-PULSE characters recover CT faster — expensive plays cost them less relative time. An enemy with PULSE 50 is genuinely terrifying: it recovers twice as fast as a PULSE 25 character.

### No WAIT Action
There is no explicit WAIT. The minimum spend is a facing change (10 CT). If a player wants to hold position they spend 10 CT to adjust facing and return to the queue quickly. Every turn you do *something*, even if minimal.

### XP
Shared after battle. All party members gain equal XP regardless of contribution. Levels are a rising stat floor. The interesting decisions live in RESONANCE and loadout.

---

## Resource Economy

### HP
Resets after every standalone battle. Persists across sequential battles within a dungeon POI. Hit zero mid-battle: character is downed, mnemonics offline for the rest of the fight. Party wipe: game over → last save. No permadeath.

### MP
Resets after every standalone battle. Persists across sequential battles within a dungeon POI. A within-battle constraint — signal-hungry mnemonics drain it; running dry means those skills go offline for the remainder of the fight.

### RESONANCE
Shared party progression resource. Earned two ways:
- **Per battle** — enemies defeated generate RESONANCE, potentially alongside loot. Fewer enemies killed means less earned. Aggressive play funds progression.
- **Per objective** — bonus RESONANCE for performance: all units survived, cleared under a turn threshold, objective completed without triggering secondary loss conditions.

Spent freely at any prep screen or world map menu on mnemonic progression. Vertical rank upgrades and permanent branch decisions. No respec. Branch choices are irreversible.

---

## Mnemonic System

### Loadout
4 slots per character at entry. Starting assumption — may change. Slot count is a minimal constraint with room to expand (gear-contributed slots, typed slots, etc.) without touching the core loop.

Loadout is selected or adjusted at the deployment screen. Seeing the map and enemy composition before committing to 4 mnemonics is the pre-battle game.

### CT Costs Replace AP Costs
Every mnemonic `.tres` file has its `ap_cost` field renamed to `ct_cost`. Same authoring, different unit. The relative weight between skills is preserved — light skills are cheap CT, heavy skills are expensive CT. The Sporlaus/Tvingar branch tradeoff still reads correctly (Sporlaus: lower CT cost, True Strike; Tvingar: same CT, 25% HP, guaranteed crit on DoT targets).

### Spatial Targeting
`TargetingData` gains two new fields:
- `range: int` — maximum cell distance from the caster
- `shape: TargetShape` — SINGLE, LINE, CONE, AREA

The GridManager computes valid target cells and communicates them for UI highlighting. The existing effect pipeline (PRE-pass, execution, POST-pass) is untouched.

### Secondary Costs
HP% and MP costs remain exactly as authored per mnemonic. CT is the action economy. HP% and MP are secondary design levers.

---

## Token Engine Changes

### ActionContext Expansion
The token engine architecture (PRE/POST pass pipeline, token self-selection via `check_trigger()`) survives entirely. `ActionContext` is expanded, not rewritten.

```gdscript
class_name ActionContext
extends RefCounted

var mnemonic: MnemonicResource
var source: CombatCharacter
var source_cell: GridCell          # new — spatial context for token range checks
var targets: Array[CombatCharacter]  # was: target (single)
var target_cells: Array[GridCell]    # new — for AoE resolution and range checks
var step_results: Array             # per-target, per-step
var total_damage: int
var any_hit: bool
var any_crit: bool
var trigger_context: ActionContext
var negated: bool
var cancelled: bool
```

`record_step()` expands to track results per target.

### Reaction Token Range
Reaction tokens gain a `reaction_range: int` field. `check_trigger()` has access to grid positions via ActionContext and verifies spatial constraints as part of trigger evaluation.

| Token | Reaction Range |
|---|---|
| COVER / INTERCEPT | 1 (must be adjacent to protectee) |
| COUNTER | 1 (melee response — cannot counter a ranged attacker across the map) |
| HAMEDO | 1 (adjacency required) |
| VIGIL | 2–3 (close support, not cross-map) |
| FOLLOW UP | TBD, mnemonic-dependent |

Reaction range becomes a design lever for mnemonic progression — a VIGIL branch that extends range as an upgrade, a COUNTER branch that sacrifices range for guaranteed crit.

### CombatCalculator
Gains grid-aware inputs: attacker cell, target cell, height delta, facing relationship. Height and facing modifiers feed into the existing hit roll calculation.

---

## Architecture

### Approach: Grid-First on a Clean Branch
New git branch. The grid system is built in complete isolation — `GridManager`, cell data, A*, movement, height, facing, spatial targeting — with zero knowledge of existing combat code. Built and refined in a standalone test scene. Once solid, the existing logic scripts adapt to the grid, not the other way around.

`boot.tscn` and the existing combat scene are untouched during grid development.

### New Folder Structure
```
scripts/grid/
  GridCell.gd        ← resource, cell data
  GridManager.gd     ← owns cells, pathfinding, occupancy, target queries
  Pathfinder.gd      ← A* implementation
scenes/grid/
  grid_test.tscn     ← isolated development sandbox
```

### Build Order (Grid Phase)
1. `GridCell` resource
2. `GridManager` — build a grid, answer "what cells can this unit reach?"
3. A* pathfinding with height and terrain costs
4. Facing and height relationship queries
5. Spatial targeting shapes on the grid

### What Survives Untouched
- CT/PULSE turn order logic (`TurnTracker`)
- ActionPipeline (PRE-pass, execution, POST-pass structure)
- SkillExecutor and effect step resolution
- Token architecture (passive, reaction, grant, instant, remove)
- MnemonicResource structure (`ap_cost` → `ct_cost` rename only)
- CombatEvents bus
- CombatFSM two-FSM architecture (Logic + UI)
- Character stat system (VitalsComponent, StatsComponent)

### What Changes
- `ActionContext` — multi-target, spatial context fields (see above)
- `CombatCharacter` — gains `grid_position: Vector2i` and `facing`
- `CombatCalculator` — grid-aware inputs for height and facing modifiers
- `TargetingData` — gains `range` and `shape` fields
- `CombatScene` → `BattleScene`, rebuilt around the grid
- Reaction tokens — gain `reaction_range` field and spatial check in `check_trigger()`
- Random encounter trigger system: removed

### What's New
- `GridCell` resource
- `GridManager` — cell array, pathfinding, occupancy, valid target queries
- `Pathfinder` — A* on the logical grid
- `BattleDeployment` — pre-battle screen, spawn cell selection, enemy inspection
- `WorldMap` — node graph, POI types, directional traversal
- Enemy AI component — movement and action decisions on the grid
- Silhouette shader — unit outline through occluding geometry
- Movement state in Logic FSM

### Parked for Later
- Camera rotation (stretch goal — assess after maps are authored)
- Surround mechanic (adjacency count, zero architecture cost to add)
- LinkUp mechanic (spatial sync between characters — needs dedicated design session)
- Trap system
- Spell-created obstacles
- Camp feature
