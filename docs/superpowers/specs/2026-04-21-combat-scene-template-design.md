# Combat Scene Template — Design Spec
**Date:** 2026-04-21
**Status:** AGREED — ready for implementation plan
**Scope:** The authored spatial foundation of combat — slot positions, camera, static framing anchors, and the loading/registration model that ties each area's combat scene to its overworld counterpart. Does not cover combat visuals, HUD, or the combat loop.

---

## The Problem

The current `CombatScene` lives as a permanent child of `GameManager`. This means:
- Slot positions can only be authored once (no per-area variation if ever needed)
- The scene structure conflates the runtime coordinator (GameManager) with authored stage data
- There is no clear "home" for the camera that frames the battlefield

More importantly: each overworld area already ships with its own `EncounterManager` holding area-specific `CombatEnvironment` and `CombatBGM`. The combat scene should live alongside the overworld scene it belongs to — not floating in an autoload.

---

## Architecture

### Loading Model

Each overworld scene loads its companion combat scene as a **disabled child**. Both enter the tree together. The combat scene self-registers with GameManager on `_enter_tree` and clears on `_exit_tree`. GameManager never reaches into the overworld tree to find it — the scene declares itself.

```
forest.tscn
  ├── [overworld geometry, EncounterManager, player...]
  └── ForestCombatScene  (process_mode: Disabled)
        └── inherits combat_scene.tscn
```

### Self-Registration

`CombatScene.gd` (the base script) handles registration for all area variants:

```gdscript
func _enter_tree() -> void:
    GameManager.current_combat_scene = self

func _exit_tree() -> void:
    GameManager.current_combat_scene = null
```

No per-area scripts needed. Inherited scenes get this for free.

### GameManager Changes

`game_manager.gd` gains one variable and uses it instead of its old `$CombatScene` child reference:

```gdscript
var current_combat_scene: CombatScene = null
```

`_on_encounter_triggered` enables `current_combat_scene` and calls `current_combat_scene.initialize(...)`. `end_combat()` disables it. The existing signal signature (`composition`, `environment`, `bgm`) does **not change** — EncounterManager still provides these from its own children.

`game_manager.tscn` loses its instanced `CombatScene` child.

---

## `combat_scene.tscn` — The Base Template

Every area's combat scene inherits from this. It is the single source of truth for slot positions, camera framing, and stage anchors.

### Scene Tree

```
CombatScene (Node, script: CombatScene.gd)
  ├── EnvironmentMount (Node3D)     — per-area 3D backdrop instanced here at runtime
  ├── BGMPlayer (AudioStreamPlayer) — receives stream from initialize()
  ├── PlayerSpawner                 — 3 permanent CombatCharacter slots
  ├── EnemySpawner                  — 6 slots, enemies spawned/cleared per encounter
  ├── Camera3D                      — orthographic, same angle as overworld, framing the full battlefield
  └── CameraTargets (Node)          — static framing anchors for the future camera controller
        ├── PlayerSide (Node3D)     — near the player cluster
        ├── Center (Node3D)         — mid-battlefield
        └── EnemySide (Node3D)      — near the enemy cluster
```

### Slot Layout

Players occupy the **lower-left** of the frame; enemies occupy the **upper-right**. Both parties face each other along a diagonal axis, consistent with the camera angle.

- **PlayerSpawner**: 3 `Node3D` slots, staggered in a loose triangle in the lower-left quadrant. Authored in the editor.
- **EnemySpawner**: 6 `Node3D` slots, spread across the upper-right quadrant. Authored in the editor.

Exact world-space coordinates are authored in the Godot editor. The intent: all slots are visible without the camera moving, and the two parties are clearly spatially separated.

### Camera3D

- **Projection**: Orthographic
- **Size**: 3.0 (matches overworld SubViewport camera)
- **Rotation**: Same isometric angle as the overworld camera
- **Position**: Authored in the editor to frame all 9 slots (3 player + 6 enemy) with reasonable padding

The camera is **static** for now. The future camera controller spec will animate it between `CameraTargets` and character `global_position` targets. The `Camera3D` node stays in place; only its transform changes.

### CameraTargets

Three authored `Node3D` positions for the future camera controller:
- `PlayerSide` — an establishing shot of the player party
- `Center` — shows the full battlefield
- `EnemySide` — an establishing shot of the enemy group

These are authored in the editor. They cost nothing now and will be used when the camera controller spec is implemented.

---

## CombatCharacter — Anchor Simplification

The existing `combat-visuals` spec described `VFXAnchor` and `CombatTextAnchor` as separate children of `CombatCharacter`, plus a `get_anchor()` method. **These are not built.**

The `CombatCharacter` root sits at its slot position and never moves (only `CombatVisuals` tweens its local position during actions). Therefore `character.global_position` IS the slot anchor. VFX, combat text, and camera targeting all use it directly — no child nodes, no lookup method.

```
CombatCharacter (Node3D)  ← root = the anchor. global_position == slot position always.
  ├── VitalsComponent
  ├── ActiveTokens
  ├── CombatVisuals (Node3D)
  │     └── AnimatedSprite3D
  └── CombatSFXComponent
```

---

## Player vs Enemy Spawning

Both spawners work identically: **instantiate on encounter start, free on encounter end.** There is no permanent pre-placed CombatCharacter for players. A fresh node guarantees fresh state — no reset logic, no lingering visuals, no hidden bugs from a previous encounter.

**PlayerSpawner**: on `initialize()`, reads party slots from `PartyManager`, instantiates a `CombatCharacter` per occupied slot, calls `initialize_player()`. On `clear()`, frees all children of each slot node.

**EnemySpawner**: same pattern — instantiate from `CombatConfig` on `initialize()`, free on `clear()`.

Slot nodes themselves (`Slot1`, `Slot2`, etc.) are permanent authored `Node3D` children of each spawner. The `CombatCharacter` instances that occupy them are not.

---

## What Stays the Same

- `encounter_triggered(composition, environment, bgm)` signal — no change
- `EncounterManager` structure — CombatBGM + CombatEnvironment stay as its children
- `EnemySpawner.gd` and `PlayerSpawner.gd` scripts — no changes needed
- `CombatScene.initialize(composition, environment, bgm)` — same signature, same logic

---

## Placeholder Environment

For testing before any area has a real `CombatEnvironment` scene: a flat `CSGBox3D` (or `MeshInstance3D` with a `PlaneMesh`) placed directly in the base `combat_scene.tscn` as a visual floor. It gets hidden or replaced when a real environment is instanced into `EnvironmentMount`. This is the only placeholder asset the template needs.

---

## What This Enables

Once the template is built and the test overworld scene has a companion combat scene:

- Walk the player → StepCounter hits threshold → encounter_triggered fires → fade → combat scene enables with authored slot positions, camera framing the battlefield → enemy characters spawn at their slots → log output confirms everything
- The camera is static but correct. No black void, no default camera.
- PlayerSpawner will skip empty slots silently (PartyManager has no data yet) — expected.
- EnemySpawner will spawn from the test `CombatConfig` — one visible enemy confirms the pipe works end to end.

---

## Out of Scope

- Camera controller behaviour (future spec)
- `CombatVisuals` animation beat API (existing spec: `2026-04-13-combat-visuals-design.md`)
- HUD layout (`2026-04-16-combat-hud-design.md`)
- Combat loop / FSM
- Per-area authored combat scenes beyond the test map
