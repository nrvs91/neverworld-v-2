# Area / Zone Architecture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> This plan is written for you to implement yourself. Each task explains what to build and why. When something is unclear, ask.

> **No automated tests in this project.** Verification steps mean: open Godot, run the scene (F5), check the Output panel for `Log.*` messages and errors.

**Goal:** Migrate the codebase from "one main.tscn with everything in it" to a Zone-based architecture: Area resources for world organisation, Zone scenes with a fixed structural template (System / SpawnPoints / NPCs / Items / Triggers / Puzzles / Exploration / Combat), persistent player pawn owned by GameManager, on-demand combat instantiation, and a clean state machine that survives multi-frame transitions.

**Architecture:** Big-picture refactor done in phases. Each phase ends with a runnable game that's still better than where you started. We rename and relocate existing pieces (EncounterManager → Combat container, main.tscn → first Zone) before introducing genuinely new ones (Exploration container, ZoneExit, Area resource, second test zone).

**Spec:** `docs/superpowers/specs/2026-04-25-area-zone-architecture-design.md`

**Tech Stack:** Godot 4.6, GDScript only. Use `Log.*` not `print()`. Manual verification via F5 in the Godot editor.

---

## Phases at a Glance

| # | Phase | Tasks | Status | What works after |
|---|---|---|---|---|
| 0 | Verification spike | 1 | ✅ DONE | Confirm the load-bearing assumption (process-disabled rendering) before touching real code |
| 1 | Combat scene lifecycle refactor | 3 | ✅ DONE | CombatScene instantiated on demand instead of permanent disabled child |
| 2 | EncounterManager → CombatSetup rename | 1 | ✅ DONE | Same orchestration logic with the new identity |
| 3 | Exploration container | 3 | ✅ DONE | New ExplorationSetup subtree mirroring CombatSetup |
| 4 | Zone template + test zone | 3 | ✅ DONE | zone_template.tscn + rowahl_plains.tscn loading via GameManager export |
| 5 | Player pawn lifecycle | 3 | ✅ DONE | Pawn lives under GameManager, lazily instantiated, frozen during combat |
| 6 | Camera rebinding | 2 | ⏳ NEXT | RemoteTransform3D follow-camera, rebound per zone load |
| 7 | TRANSITIONING state + zone-to-zone transitions | 4 | ⬜ TODO | Second test zone, ZoneExit triggers, working zone-to-zone with state guards |
| 8 | Area resource | 2 | ⬜ TODO | First test Area .tres, GameManager loads entry zone from Area |

---

## Deviations from Plan (as-built, 2026-04-27)

These are intentional divergences made during implementation. The plan below reflects the original design; these notes describe what actually shipped.

| Plan said | What was built | Why |
|---|---|---|
| Rename EncounterManager → `Combat` | Renamed to `CombatSetup` | `Combat` was too bare as a class_name — `CombatSetup` is unambiguous |
| Rename `Exploration` container | Named `ExplorationSetup` | Symmetry with `CombatSetup` |
| `ExplorationBGM extends Node` with internal `AudioStreamPlayer` | `ExplorationBGM extends AudioStreamPlayer` | Simpler — no wrapper needed, `play()`/`stop()` built in |
| `ExplorationEnvironment` has `instantiate_environment()`/`clear()` | `ExplorationEnvironment` is a pure data holder (`@export var scene: PackedScene` only) | The container doesn't need those methods yet; GameManager drives loading |
| `Exploration` has `enter()`/`exit()` | `ExplorationSetup` has `pause_for_combat()`/`resume_after_combat()` only | Full enter/exit lifecycle deferred until zone-to-zone transitions (Phase 7) |
| Scripts in `scripts/exploration/` | Scripts in `scripts/zones/` | Better reflects gameplay context |
| Scenes in `scenes/exploration/` | Scenes in `scenes/zones/setup/` | Same reason |
| Restructure `main.tscn` into Zone template in-place | Created `zone_template.tscn` + `rowahl_plains.tscn` fresh; `main.tscn` kept as sandbox | Cleaner to build correct from scratch than restructure a legacy scene |
| `overworld_character.tscn` modified in place, components added | `overworld_character.tscn`/`.gd` deleted; `player_overworld.tscn`/`PlayerOverworld.gd` created | Composition insight: each actor type is its own scene; no shared god-template |
| `GameManager` loads initial zone via hardcoded `main.tscn` string | `GameManager` has `@export var starting_zone: PackedScene` | Removes hardcoded path; Area resource wires in during Phase 8 |
| Pawn freeze wired in Task 13 (separate step) | Pawn freeze wired during Phase 5 together with pawn lifecycle | Natural to do at the same time |

---

## File Map

### What stays unchanged
- `scripts/combat/CombatCharacter.gd`, `scripts/combat/PlayerSpawner.gd`, `scripts/combat/EnemySpawner.gd`, `scripts/combat/CombatScene.gd` (mostly — small `cleanup()` removal)
- `scripts/combat/CombatCalculator.gd`, all token / vitals / visuals / sfx components — untouched
- `scripts/exploration/StepCounter.gd`, `scripts/exploration/EncounterPool.gd`, `scripts/exploration/CombatBGM.gd`, `scripts/exploration/CombatEnvironment.gd` — untouched (they were already correct)
- `scripts/characters/overworld_character.gd` and its components — untouched. The `.tscn` file is also untouched. Only its parent in the runtime tree changes.
- All autoloads (`PartyManager`, `CombatEvents`, `ExplorationEvents`, `Globals`, `Log`, `Enums`)

### What gets renamed/moved
- `scripts/exploration/EncounterManager.gd` → `scripts/exploration/Combat.gd` (class rename, same logic)
- `scenes/encounter_manager.tscn` → `scenes/exploration/combat.tscn`
- `main.tscn` — restructured in place into the new Zone template

### What gets created
- `scripts/exploration/exploration.gd` (Exploration container script)
- `scenes/exploration/exploration.tscn` (Exploration template scene)
- `scripts/exploration/exploration_environment.gd` (PackedScene holder, mirrors `CombatEnvironment.gd`)
- `scenes/exploration/exploration_environment.tscn`
- `scripts/exploration/exploration_bgm.gd` (AudioStream holder, mirrors `CombatBGM.gd`)
- `scenes/exploration/exploration_bgm.tscn`
- `scripts/exploration/zone_exit.gd`
- `scenes/exploration/zone_exit.tscn`
- `scripts/exploration/area.gd` (Resource class)
- `resources/areas/test_area.tres` (example Area resource)
- `scenes/exploration/zones/forest_path_environment.tscn` (geometry extracted from main.tscn)
- `scenes/exploration/zones/test_zone_b.tscn` (second test zone for transition verification)

### What gets modified
- `scripts/core/game_manager.gd` — significant changes (combat lifecycle, pawn lifecycle, zone loading, state guards)
- `scenes/core/game_manager.tscn` — remove permanent CombatScene child, add CurrentZone slot if not present
- `autoloads/CombatEvents.gd` — add `scripted_encounter_triggered` signal
- `autoloads/ExplorationEvents.gd` — add `zone_exit_requested` signal
- `autoloads/Enums.gd` — add `TRANSITIONING` state to `GameState` enum
- `scripts/combat/CombatScene.gd` — remove obsolete `cleanup()` method

---

## Phase 0 — Verification Spike

The whole architecture leans on one Godot 4.6 behaviour: that `WorldEnvironment` and `DirectionalLight3D` keep rendering when their parent is `process_mode = PROCESS_MODE_DISABLED`. This SHOULD be true (rendering isn't gated on `_process` callbacks), but if it isn't, the design needs revisiting before any real work happens.

### Task 1 — Spike: confirm process-disabled rendering

**What and why:** Build a minimal isolated test scene that verifies render nodes keep drawing when their parent is process-disabled. Don't touch any real game code. If this fails, we stop and rethink before the real migration.

**Files:**
- Create: `scenes/spikes/process_disabled_render_test.tscn`
- Create: `scripts/spikes/process_disabled_render_test.gd`

- [x] **Step 1: Create the spike scene**

In the Godot editor, create a new scene at `scenes/spikes/process_disabled_render_test.tscn`. Root is a plain `Node` named `SpikeRoot`. Children:

```
SpikeRoot (Node + script below)
├── EnvWrapper (Node)
│   ├── WorldEnvironment       ← assign an Environment.tres with non-default ambient (e.g., red tint)
│   └── DirectionalLight3D     ← rotate to point at the box from a recognisable angle
├── Camera3D                   ← orthographic, current=true, framed on the box
└── TestBox (MeshInstance3D)   ← BoxMesh with a StandardMaterial3D
```

Save the scene.

- [x] **Step 2: Add the spike script**

Create `scripts/spikes/process_disabled_render_test.gd`:

```gdscript
extends Node

@onready var env_wrapper: Node = $EnvWrapper

func _ready() -> void:
    Log.info("Spike: scene running with EnvWrapper enabled. Box should be lit by ambient + directional.")
    Log.info("Spike: in 2 seconds, EnvWrapper.process_mode = DISABLED. If rendering keeps working, the box stays lit.")
    await get_tree().create_timer(2.0).timeout
    env_wrapper.process_mode = Node.PROCESS_MODE_DISABLED
    Log.info("Spike: EnvWrapper now DISABLED. Box should still be lit (assumption holds) or go dark/lose ambient (assumption broken).")
```

Attach the script to `SpikeRoot` in the editor. Save.

- [x] **Step 3: Run the spike scene directly**

In the Godot editor, with `process_disabled_render_test.tscn` open, press **F6** (Run Current Scene), not F5. F5 runs the main scene; F6 runs the open scene. You should see:

- The cube lit (red-tinted ambient + directional shading) for 2 seconds
- After 2 seconds, the cube **stays lit** in the same way

Output panel should show all three `Log.info` lines and **no errors**.

- [x] **Step 4: Document the result**

If the cube stays lit after disable: the architecture is sound. Continue to Phase 1.

If the cube goes dark or loses lighting after disable: **stop**. The per-zone-lighting story doesn't work and the spec needs revisiting. Add a note to the spec under a new "Verification Result" section explaining what happened, then have a conversation about alternative architectures (e.g., GameManager owning lighting persistently).

- [x] **Step 5: Commit (whichever direction)**

```bash
git add scenes/spikes/process_disabled_render_test.tscn scripts/spikes/process_disabled_render_test.gd
git commit -m "Add process-disabled render spike to verify per-zone lighting assumption"
```

If the assumption holds, the spike scene can stay in `scenes/spikes/` as documentation. It's not a test, but it's a reproducible verification that future-you can re-run if the lighting story ever feels off.

---

## Phase 1 — Combat Scene Lifecycle Refactor

The spec changes how `CombatScene` is owned. Instead of a permanent disabled child of GameManager, it becomes a `PackedScene` constant that's instantiated on demand and freed on combat end. This phase makes that swap and removes the now-obsolete `cleanup()` method.

### Task 2 — Add the `scripted_encounter_triggered` signal

**What and why:** This is the smallest possible change to verify the refactor pipeline still produces a runnable game. It also sets up the structural seam for boss/story-fight triggers that we'll wire in later phases. Just adding the signal — no emitters, no handlers yet.

**Files:**
- Modify: `autoloads/CombatEvents.gd`

- [x] **Step 1: Find the existing `encounter_triggered` declaration**

Open `autoloads/CombatEvents.gd`. You'll see the existing signal:

```gdscript
signal encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
```

- [x] **Step 2: Add `scripted_encounter_triggered` directly below it**

```gdscript
signal encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
signal scripted_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
```

Same payload shape. Different intent.

- [x] **Step 3: Run the game**

Press F5. The game should run normally — main menu (or dev_mode jump to overworld), step counter ticking, encounter triggering, combat playing. Nothing visible should change because nothing emits the new signal yet.

Check the Output panel: no errors, no warnings about the new signal.

- [x] **Step 4: Commit**

```bash
git add autoloads/CombatEvents.gd
git commit -m "Add scripted_encounter_triggered signal alongside encounter_triggered"
```

---

### Task 3 — Convert `CombatScene` to on-demand instantiation

**What and why:** Currently `CombatScene` lives as a permanent disabled child of GameManager. The refactor: GameManager holds a `PackedScene` constant + an `_current_combat` instance var. On encounter, instantiate fresh and add as child. On end, `queue_free()`. Symmetric with how zones will load.

**Files:**
- Modify: `scripts/core/game_manager.gd`
- Modify: `scenes/core/game_manager.tscn` (remove permanent CombatScene child)

- [x] **Step 1: Open `scripts/core/game_manager.gd` and find the existing combat reference**

You'll see at the top:

```gdscript
@onready var combat_scene: CombatScene = $CombatScene
```

And in `_ready()`:

```gdscript
combat_scene.process_mode = Node.PROCESS_MODE_DISABLED
```

These are about to disappear.

- [x] **Step 2: Replace the `@onready` with a preload constant + instance var**

Remove the `@onready var combat_scene` line. Add at the top of the script body, just after `extends Node`:

```gdscript
const CombatSceneTemplate: PackedScene = preload("res://scenes/combat/combat_scene.tscn")
var _current_combat: CombatScene = null
```

- [x] **Step 3: Remove the `_ready()` line that disabled the combat scene**

Delete this line:

```gdscript
combat_scene.process_mode = Node.PROCESS_MODE_DISABLED
```

It served the old permanent-child design and means nothing now.

- [x] **Step 4: Rewrite `_on_encounter_triggered`**

Find the current handler. Replace its body with:

```gdscript
func _on_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
    if state != Enums.GameState.OVERWORLD:
        return
    Log.info("Encounter triggered, transitioning to combat")
    _overworld_camera = get_viewport().get_camera_3d()
    await screen_fader.fade_out()
    _current_combat = CombatSceneTemplate.instantiate()
    add_child(_current_combat)
    _current_combat.initialize(composition, environment, bgm)
    current_overworld.process_mode = Node.PROCESS_MODE_DISABLED
    state = Enums.GameState.COMBAT
    await screen_fader.fade_in()
```

Note: `state = Enums.GameState.COMBAT` happens **before** fade-in. We'll add the proper TRANSITIONING state in Phase 7. For now, the existing OVERWORLD/COMBAT model continues to work.

- [x] **Step 5: Rewrite `end_combat`**

Replace the body with:

```gdscript
func end_combat() -> void:
    Log.info("Combat finished, transitioning to overworld")
    await screen_fader.fade_out()
    _current_combat.queue_free()
    _current_combat = null
    current_overworld.process_mode = Node.PROCESS_MODE_INHERIT
    if _overworld_camera != null:
        _overworld_camera.make_current()
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
```

`queue_free()` recursively frees children, so the spawners, environment mount contents, BGM player — all get cleaned up automatically.

- [x] **Step 6: Open `scenes/core/game_manager.tscn` in the Godot editor**

Find the `CombatScene` child node in the scene tree. **Right-click → Delete**. This removes the permanent disabled child. The scene now has just `ScreenFader`, `CurrentScene`, and any other persistent children.

Save the scene.

- [x] **Step 7: Run the game and trigger combat**

Press F5. Walk until an encounter triggers. You should see:

- `Encounter triggered, transitioning to combat`
- The fade out, then combat scene appears (instantiated fresh)
- Combat camera framing the arena
- `CombatScene initialized` (or whatever your initialize method logs)
- No errors about missing `$CombatScene` node

Now trigger end_combat (your debug key, or however you currently exit combat). You should see:

- `Combat finished, transitioning to overworld`
- The fade out, no errors during free
- Fade in back to overworld
- The pawn at the same position it was before combat

If you trigger another encounter, the same cycle works again with a fresh `_current_combat` instance.

- [x] **Step 8: Commit**

```bash
git add scripts/core/game_manager.gd scenes/core/game_manager.tscn
git commit -m "Convert CombatScene to on-demand instantiation, remove permanent disabled child"
```

---

### Task 4 — Remove the obsolete `CombatScene.cleanup()` method

**What and why:** Now that GameManager calls `queue_free()` on `_current_combat`, all children of the combat scene get freed automatically. The explicit `cleanup()` method that was added in the 2026-04-21 plan is no longer called by anyone and serves no purpose.

**Files:**
- Modify: `scripts/combat/CombatScene.gd`

- [x] **Step 1: Open `scripts/combat/CombatScene.gd`**

You'll see the `cleanup()` method:

```gdscript
func cleanup () -> void:
    player_spawner.clear()
    enemy_spawner.clear()
    bgm_player.stop()
    for i in environment_mount.get_children():
        i.queue_free()
    Log.info("CombatScene cleaned up.")
```

- [x] **Step 2: Verify nothing calls `cleanup()`**

Run a project-wide search for `cleanup(` (Godot Editor → Project → Search in Files, or grep). Expected: no matches outside of `CombatScene.gd` itself. If anything does call it, fix that caller before deleting the method.

```bash
grep -r "cleanup()" /home/bart/Projects/neverworld-v-2/scripts/
```

- [x] **Step 3: Delete the method entirely**

Remove the whole `cleanup()` block from `CombatScene.gd`. Save.

- [x] **Step 4: Run the game**

Press F5. Trigger combat, end combat, trigger combat again. No errors about missing methods. The behaviour should be identical to Task 3's verification — `queue_free()` does the cleanup work.

- [x] **Step 5: Commit**

```bash
git add scripts/combat/CombatScene.gd
git commit -m "Remove obsolete CombatScene.cleanup() — queue_free handles it now"
```

---

## Phase 2 — EncounterManager → Combat Rename

The current `EncounterManager` is structurally exactly what the spec calls the `Combat` container. Rename and relocate without changing logic — keep the changeset boring so any regressions are obvious.

### Task 5 — Rename `EncounterManager` to `Combat`

**What and why:** The script and scene get renamed. `class_name` changes. The reference in `main.tscn` updates. Logic is unchanged.

**Files:**
- Rename: `scripts/exploration/EncounterManager.gd` → `scripts/exploration/Combat.gd`
- Rename: `scenes/encounter_manager.tscn` → `scenes/exploration/combat.tscn`
- Modify: `main.tscn` (update path reference + node name)

- [x] **Step 1: Move and rename the script file**

```bash
git mv scripts/exploration/EncounterManager.gd scripts/exploration/Combat.gd
```

- [x] **Step 2: Update the script's `class_name` and the inner field types**

Open `scripts/exploration/Combat.gd`. Change the top:

```gdscript
class_name Combat
extends Node
```

The rest of the file logic (`@onready var step_counter`, `_on_threshold_reached`, etc.) stays exactly as is.

- [x] **Step 3: Move and rename the scene file**

In Godot editor (closed first to avoid stale references), or via shell:

```bash
mkdir -p /home/bart/Projects/neverworld-v-2/scenes/exploration
git mv scenes/encounter_manager.tscn scenes/exploration/combat.tscn
```

Reopen the editor.

- [x] **Step 4: Update the scene's root node name and script reference**

Open `scenes/exploration/combat.tscn` in the editor. The root node is named `EncounterManager` — rename it to `Combat`. The script reference at the top of the .tscn file may already be referenced via UID, in which case Godot updates the path automatically. If it shows broken, point the script field back at `res://scripts/exploration/Combat.gd`.

Save the scene.

- [x] **Step 5: Update `main.tscn` to reference the renamed scene and node**

Open `main.tscn` in the editor. Find the existing `EncounterManager` instance under `System/`. The instance reference (PackedScene path) should auto-update via UID, but the node name will still say `EncounterManager`. Rename the instance node to `Combat`.

Save `main.tscn`.

- [x] **Step 6: Run the game and trigger an encounter**

Press F5. The encounter pipeline should still work end-to-end:

- StepCounter ticks
- `EncounterPool picked: ...` log
- Combat triggers, fade out, combat scene loads
- Return from combat, etc.

If the editor logs about the script's old class name (`EncounterManager`) being referenced anywhere — find and fix those references. With `class_name Combat`, anywhere that previously typed a variable as `EncounterManager` needs updating. Search:

```bash
grep -rn "EncounterManager" /home/bart/Projects/neverworld-v-2/scripts/
```

If any matches, update them to `Combat`. Common locations: GameManager (probably none), test code (none in this project).

- [x] **Step 7: Commit**

```bash
git add scripts/exploration/Combat.gd scenes/exploration/combat.tscn main.tscn
git commit -m "Rename EncounterManager to Combat — same logic, new identity"
```

---

## Phase 3 — Exploration Container

Mirror the Combat container with a parallel Exploration container. New thin holder nodes (`ExplorationEnvironment`, `ExplorationBGM`), one new container script that orchestrates them, slotted into `main.tscn` as a sibling of Combat.

### Task 6 — Create `ExplorationBGM` (audio stream holder)

**What and why:** Mirror of `CombatBGM` — a thin Node holder for an `AudioStream` reference, with a small play/stop API so the Exploration container script can drive it. Keeping it as its own node makes the data point inspectable in the editor and matches the combat-side pattern.

**Files:**
- Create: `scripts/exploration/ExplorationBGM.gd`
- Create: `scenes/exploration/exploration_bgm.tscn`

- [x] **Step 1: Create the script**

Create `scripts/exploration/ExplorationBGM.gd`:

```gdscript
class_name ExplorationBGM
extends Node

# Authored per-zone. The BGM track played during exploration in this zone.
@export var stream: AudioStream

@onready var _player: AudioStreamPlayer = AudioStreamPlayer.new()

func _ready() -> void:
    add_child(_player)

func play() -> void:
    if stream == null:
        Log.warn("ExplorationBGM.play() called but stream is null")
        return
    _player.stream = stream
    _player.play()
    Log.info("ExplorationBGM playing")

func stop() -> void:
    _player.stop()
    Log.info("ExplorationBGM stopped")
```

The internal `AudioStreamPlayer` is created at runtime so the scene file stays clean — only one node, one export.

- [x] **Step 2: Create the scene**

In the Godot editor, create a new scene at `scenes/exploration/exploration_bgm.tscn`. Single root: `Node`, name `ExplorationBGM`, attach the script you just wrote. Leave `stream` empty (it'll be set per-zone later). Save.

- [x] **Step 3: Run the game**

F5. The new files don't change runtime behaviour yet — just verify nothing about adding the script broke parsing.

Output panel: no errors.

- [x] **Step 4: Commit**

```bash
git add scripts/exploration/ExplorationBGM.gd scenes/exploration/exploration_bgm.tscn
git commit -m "Add ExplorationBGM node — AudioStream holder mirroring CombatBGM"
```

---

### Task 7 — Create `ExplorationEnvironment` (geometry holder)

**What and why:** Mirror of `CombatEnvironment` — a thin Node holder for a `PackedScene` reference, with a small `instantiate()` / `clear()` API. The Exploration container will use it on zone enter/exit. Keeps geometry decoupled from the zone structure (you can swap it without touching the zone scene).

**Files:**
- Create: `scripts/exploration/ExplorationEnvironment.gd`
- Create: `scenes/exploration/exploration_environment.tscn`

- [x] **Step 1: Create the script**

Create `scripts/exploration/ExplorationEnvironment.gd`:

```gdscript
class_name ExplorationEnvironment
extends Node3D

# Authored per-zone. The geometry scene that gets instantiated on zone enter.
@export var scene: PackedScene

func instantiate_environment() -> void:
    clear()
    if scene == null:
        Log.warn("ExplorationEnvironment.instantiate_environment() called but scene is null")
        return
    var instance: Node = scene.instantiate()
    add_child(instance)
    Log.info("ExplorationEnvironment instantiated:", scene.resource_path)

func clear() -> void:
    for child in get_children():
        child.queue_free()
    Log.info("ExplorationEnvironment cleared")
```

`extends Node3D` rather than `Node` — geometry needs a 3D parent so child mesh nodes inherit a transform. The combat-side `CombatEnvironment` script extends `Node` because the combat scene's `EnvironmentMount` is the actual `Node3D` parent. Here we collapse those two roles.

- [x] **Step 2: Create the scene**

Create `scenes/exploration/exploration_environment.tscn`. Root: `Node3D` named `ExplorationEnvironment`, attach the script. Leave `scene` empty. Save.

- [x] **Step 3: Run the game**

F5. No behavioural change yet. Verify no parse errors.

- [x] **Step 4: Commit**

```bash
git add scripts/exploration/ExplorationEnvironment.gd scenes/exploration/exploration_environment.tscn
git commit -m "Add ExplorationEnvironment node — PackedScene holder for zone geometry"
```

---

### Task 8 — Create the `Exploration` container scene + script

**What and why:** The container that orchestrates `ExplorationEnvironment` + `ExplorationBGM`. On zone enter, calls `instantiate_environment()` and `play()`. Mirrors how the (renamed) `Combat` container orchestrates its children.

**Files:**
- Create: `scripts/exploration/Exploration.gd`
- Create: `scenes/exploration/exploration.tscn`

- [x] **Step 1: Create the script**

Create `scripts/exploration/Exploration.gd`:

```gdscript
class_name Exploration
extends Node

@onready var environment: ExplorationEnvironment = $ExplorationEnvironment
@onready var bgm: ExplorationBGM = $ExplorationBGM

func enter() -> void:
    environment.instantiate_environment()
    bgm.play()
    Log.info("Exploration: entered zone")

func exit() -> void:
    bgm.stop()
    environment.clear()
    Log.info("Exploration: exited zone")

func pause_for_combat() -> void:
    bgm.stop()
    Log.info("Exploration: BGM paused for combat")

func resume_after_combat() -> void:
    bgm.play()
    Log.info("Exploration: BGM resumed after combat")
```

`enter()`/`exit()` are full lifecycle hooks called by GameManager on zone load/unload. `pause_for_combat()`/`resume_after_combat()` are narrower — only stop/start BGM without touching the environment, called when combat begins or ends inside the same zone. The container doesn't store state; it just routes lifecycle calls to its children.

- [x] **Step 2: Create the scene**

Create `scenes/exploration/exploration.tscn`. Root: `Node` named `Exploration`, attach the script. Add child instances:

```
Exploration (Node + Exploration.gd)
├── ExplorationEnvironment    ← instance of exploration_environment.tscn
└── ExplorationBGM            ← instance of exploration_bgm.tscn
```

Save.

- [x] **Step 3: Run the game**

F5. The Exploration scene exists but isn't instanced anywhere yet. No behaviour change. Verify no parse errors.

- [x] **Step 4: Commit**

```bash
git add scripts/exploration/Exploration.gd scenes/exploration/exploration.tscn
git commit -m "Add Exploration container — symmetric partner to Combat"
```

---

## Phase 4 — Main.tscn → Zone Restructure

Restructure `main.tscn` to match the Zone template. Pull geometry out into a separate scene (referenced by the new `ExplorationEnvironment`). Set up the `System` node properly. Add `SpawnPoints`. Reposition the existing `Combat` container as a Zone-level sibling instead of being nested in `System`.

### Task 9 — Extract geometry from `main.tscn` into a separate scene

**What and why:** `main.tscn` currently has `Floor`, `MeshInstance3D`, `MeshInstance3D2` directly as children. Move them into a new scene at `scenes/exploration/zones/forest_path_environment.tscn` so the `ExplorationEnvironment` PackedScene reference has something to point at.

**Files:**
- Create: `scenes/exploration/zones/forest_path_environment.tscn`
- Modify: `main.tscn`

- [x] **Step 1: Create the geometry scene**

In the Godot editor, create a new scene at `scenes/exploration/zones/forest_path_environment.tscn`. Root: `Node3D` named `ForestPathEnvironment`. Save (you'll need to make the directory first if it doesn't exist).

```bash
mkdir -p /home/bart/Projects/neverworld-v-2/scenes/exploration/zones
```

- [x] **Step 2: Move geometry from main.tscn into the new scene**

In Godot editor, open `main.tscn`. Select `Floor` (the green plane), `MeshInstance3D` (the pink sphere), and `MeshInstance3D2` (the cyan box). Cut them (Ctrl+X).

Open `scenes/exploration/zones/forest_path_environment.tscn`. Select the root `ForestPathEnvironment` node and paste (Ctrl+V). The three meshes should appear as children with their original transforms preserved.

Save the geometry scene.

- [x] **Step 3: Verify main.tscn is intact otherwise**

Back in `main.tscn`, the geometry should be gone but everything else (WorldEnvironment, DirectionalLight3D, CameraRig, overworld_character, System/Combat) should still be there. Save `main.tscn`.

- [x] **Step 4: Run the game (transitional state — expect a placeholder world)**

F5. The main scene will run, but it'll look empty (no floor, no shapes) because we haven't yet wired the new geometry scene back via `ExplorationEnvironment`. The character will fall through where the floor was. Don't be alarmed — this is expected for one task.

Output panel: no errors. The character/scene is broken visually but logically running.

- [x] **Step 5: Commit (broken visual state, will be fixed in Task 10)**

```bash
git add main.tscn scenes/exploration/zones/forest_path_environment.tscn
git commit -m "Extract main.tscn geometry into forest_path_environment.tscn"
```

---

### Task 10 — Add `Exploration` container to main.tscn, wire the geometry

**What and why:** Add an instance of `exploration.tscn` to `main.tscn`. Set its `ExplorationEnvironment.scene` export to point at `forest_path_environment.tscn`. Have GameManager call `Exploration.enter()` after the overworld loads. Geometry should appear again.

**Files:**
- Modify: `main.tscn`
- Modify: `scripts/core/game_manager.gd`

- [x] **Step 1: Instance Exploration into main.tscn**

Open `main.tscn`. Select the root node. Add an instance of `scenes/exploration/exploration.tscn` as a direct child. The new tree section looks like:

```
Main
├── ...existing nodes...
├── Exploration
│   ├── ExplorationEnvironment
│   └── ExplorationBGM
└── System
    └── Combat
```

- [x] **Step 2: Wire the geometry reference**

In the editor's scene tree, click on `Exploration/ExplorationEnvironment`. In the Inspector on the right, find the `Scene` export. Drag `scenes/exploration/zones/forest_path_environment.tscn` from the FileSystem panel onto that field (or click and pick the file).

Save `main.tscn`.

- [x] **Step 3: Have GameManager call `Exploration.enter()` after loading**

Open `scripts/core/game_manager.gd`. Find `_load_overworld`:

```gdscript
func _load_overworld(path: String) -> void:
    var scene: PackedScene = load(path)
    var instance: Node = scene.instantiate()
    current_scene.add_child(instance)
    current_overworld = instance
```

Modify it to call into the loaded zone's Exploration container:

```gdscript
func _load_overworld(path: String) -> void:
    var scene: PackedScene = load(path)
    var instance: Node = scene.instantiate()
    current_scene.add_child(instance)
    current_overworld = instance
    var exploration: Exploration = instance.get_node_or_null("Exploration")
    if exploration:
        exploration.enter()
    else:
        Log.warn("_load_overworld: no Exploration node in", path)
```

The `get_node_or_null` keeps the warning soft — if main.tscn doesn't have an Exploration node yet (or after we restructure further), it logs but doesn't crash.

- [x] **Step 4: Run the game**

F5. You should see:

- `New Game started!` (or similar dev_mode flow)
- `ExplorationEnvironment instantiated: res://scenes/exploration/zones/forest_path_environment.tscn`
- `ExplorationBGM` warns about null stream (expected — we haven't assigned a stream)
- `Exploration: entered zone`
- The floor, sphere, and box should be visible again — geometry restored via the new path
- Character can walk around as before

If geometry doesn't appear, double-check the Inspector field was actually set — drag-and-drop sometimes fails silently.

- [x] **Step 5: Commit**

```bash
git add main.tscn scripts/core/game_manager.gd
git commit -m "Wire Exploration container in main.tscn — geometry loads via ExplorationEnvironment"
```

---

### Task 11 — Restructure main.tscn into proper Zone layout (System node, SpawnPoints)

**What and why:** Reorganise `main.tscn`'s tree to match the Zone template. Move `WorldEnvironment`, `DirectionalLight3D`, and `CameraRig/Camera3D` into a `System` node. Move the `Combat` container out from under `System` so it sits as a Zone-level sibling. Add a `SpawnPoints` container with a default marker.

**Files:**
- Modify: `main.tscn`

- [x] **Step 1: Open main.tscn in the editor**

Current structure (after Task 10):

```
Main
├── WorldEnvironment
├── DirectionalLight3D
├── CameraRig
│   └── Camera3D
├── overworld_character (will move out in Phase 5, leave for now)
├── Exploration
│   ├── ExplorationEnvironment
│   └── ExplorationBGM
└── System
    └── Combat
```

Target structure:

```
Main (Zone — will be renamed/replaced later)
├── System
│   ├── WorldEnvironment
│   ├── DirectionalLight3D     ← optional; you can keep or remove per spec
│   └── Camera3D               ← will be moved here from CameraRig
├── SpawnPoints
│   └── default                ← Marker3D where the player appears on zone entry
├── Exploration
├── overworld_character        ← stays here for now, removed in Phase 5
└── Combat                     ← moved out of System, becomes Zone-level sibling
```

Note: `CameraRig` is currently a Node3D wrapping the Camera3D with an offset. The spec puts `Camera3D` directly under `System`. The transform information in `CameraRig` and on the camera will need to be combined.

- [x] **Step 2: Move System children into proper position**

If `System` already exists (it does — Combat is currently inside it), reuse it. Drag `WorldEnvironment` and `DirectionalLight3D` into `System`.

- [x] **Step 3: Move Camera3D under System (preserving its world transform)**

The current setup is `CameraRig` (Node3D with offset transform) holding `Camera3D` (with its own transform inside the rig). Combine them:

a. Click on `CameraRig/Camera3D`. In the Inspector, note the global transform (Inspector shows local; the actual world position is rig × camera local).
b. Drag `Camera3D` out of `CameraRig` and drop it onto `System`. The local transform will change, but Godot may try to preserve world position depending on your setup.
c. Verify the camera is still framed on the play area. If not, adjust the camera's transform manually until it matches what was working before.
d. Delete the now-empty `CameraRig` node.

If this gets fiddly, an alternative: move `CameraRig` itself (with the camera inside) under `System`. Either works — the spec calls for `Camera3D` under `System`, but if a wrapping rig helps you author camera offsets, keep it.

- [x] **Step 4: Move Combat out of System**

In the scene tree, drag `System/Combat` out and drop it onto the root `Main` node so it becomes a Zone-level sibling of `System` and `Exploration`.

- [x] **Step 5: Add SpawnPoints container with default marker**

Add a plain `Node` as a child of `Main`, name it `SpawnPoints`. Inside it, add a `Marker3D` named `default`. Position the marker where the player should appear on zone entry (e.g., the location where `overworld_character` currently sits — match its transform).

- [x] **Step 6: Add the Triggers container**

Add a plain `Node` as a child of `Main`, name it `Triggers`. Leave it empty for now — Task 20 adds a `ZoneExit` instance to it. Even though it's empty, having the container present matches the Zone template and prevents `Triggers` becoming an inconsistent "sometimes-here" node across zones.

- [x] **Step 7: Save and run**

Save `main.tscn`. Press F5. The game should run identically to before — same camera framing, same geometry, same encounter flow. Combat should still trigger and end correctly.

If anything's broken, the most likely culprits are:
- Camera transform changed during the move — fix by adjusting the camera's transform.
- A signal wire was dropped during reorganisation — re-check connections in the editor.

Output panel: no errors related to missing nodes.

- [x] **Step 8: Commit**

```bash
git add main.tscn
git commit -m "Restructure main.tscn into Zone layout (System, SpawnPoints, Triggers, Combat sibling)"
```

---

## Phase 5 — Player Pawn Lifecycle

Move the `overworld_character` instance out of the zone scene and into GameManager-managed lazy instantiation. The character's component composition stays untouched — only its parent and lifecycle change.

### Task 12 — Move `overworld_character` out of main.tscn

**What and why:** Currently the `overworld_character` instance lives inside `main.tscn`. After this task, it lives under GameManager (instanced lazily on zone load). For now, the spawn happens immediately in `_ready` — Phase 7 adds the proper "lazy on first zone load" wiring.

**Files:**
- Modify: `main.tscn` (delete the character instance)
- Modify: `scripts/core/game_manager.gd` (add OverworldPawnTemplate, instantiate in `_ready`)

- [x] **Step 1: Delete `overworld_character` from main.tscn**

In Godot editor, open `main.tscn`. Select the `overworld_character` instance and any of its component children (`PlayerInputComponent`, `MovementComponent`, `CharacterVisualComponent`). Delete them.

Save.

- [x] **Step 2: Add the OverworldPawnTemplate constant + `_pawn` var to GameManager**

Open `scripts/core/game_manager.gd`. At the top, near the other constants:

```gdscript
const OverworldPawnTemplate: PackedScene = preload("res://scenes/characters/overworld_character.tscn")
var _pawn: Node3D = null
```

- [x] **Step 3: Instantiate the pawn after the zone loads**

Modify `_load_overworld` to spawn the pawn at the zone's default spawn point:

```gdscript
func _load_overworld(path: String) -> void:
    var scene: PackedScene = load(path)
    var instance: Node = scene.instantiate()
    current_scene.add_child(instance)
    current_overworld = instance

    if _pawn == null:
        _pawn = OverworldPawnTemplate.instantiate()
        add_child(_pawn)
        Log.info("Overworld pawn instantiated")

    var spawn_points: Node = instance.get_node_or_null("SpawnPoints")
    if spawn_points:
        var default_marker: Marker3D = spawn_points.get_node_or_null("default")
        if default_marker:
            _pawn.global_position = default_marker.global_position
        else:
            Log.error("Spawn point not found: default — falling back to Vector3.ZERO")
            _pawn.global_position = Vector3.ZERO
    else:
        Log.warn("_load_overworld: no SpawnPoints in", path)
        _pawn.global_position = Vector3.ZERO

    var exploration: Exploration = instance.get_node_or_null("Exploration")
    if exploration:
        exploration.enter()
```

- [x] **Step 4: Make sure the pawn is in the "player" group**

Open `scenes/characters/overworld_character.tscn` in the editor. With the root node selected, in the Node panel (top right area), click the **Groups** tab. Add the group `player` if it isn't already there. Save.

This matters for `ZoneExit` later — it filters trigger entries to bodies in the `player` group.

- [x] **Step 5: Run the game**

F5. You should see:
- `Overworld pawn instantiated`
- `Exploration: entered zone`
- The character spawns at the `default` Marker3D position
- Movement, encounter triggering, combat — all still work

If the character spawns at origin but you expected it at a specific spot, double-check the Marker3D was positioned correctly in Task 11.

- [x] **Step 6: Commit**

```bash
git add main.tscn scripts/core/game_manager.gd scenes/characters/overworld_character.tscn
git commit -m "Move overworld_character to GameManager-managed instantiation, add player group"
```

---

### Task 13 — Freeze the pawn during combat

**What and why:** With the pawn living under GameManager (not inside the zone), disabling the zone via `process_mode = DISABLED` doesn't reach the pawn. Without an explicit freeze, the pawn keeps reading input and moving in world space behind the combat screen. Surprising bug a few months later when someone notices the player ends up in unexpected places after fights.

**Files:**
- Modify: `scripts/core/game_manager.gd`

- [x] **Step 1: Add the pawn freeze to `_on_encounter_triggered`**

In `_on_encounter_triggered`, after `current_overworld.process_mode = Node.PROCESS_MODE_DISABLED`, add:

```gdscript
    if _pawn:
        _pawn.process_mode = Node.PROCESS_MODE_DISABLED
```

- [x] **Step 2: Add the pawn unfreeze to `end_combat`**

In `end_combat`, after `current_overworld.process_mode = Node.PROCESS_MODE_INHERIT`, add:

```gdscript
    if _pawn:
        _pawn.process_mode = Node.PROCESS_MODE_INHERIT
```

- [x] **Step 3: Verify the freeze works**

F5. Trigger combat. While the combat scene is up, the overworld should be frozen — but more importantly, the pawn should be frozen. There's no easy way to test this directly during combat (no input reaches the pawn from the combat scene anyway in current code), but you can sanity-check by adding a temporary `Log.info` in `MovementComponent._physics_process` that prints when it runs. Before this fix, that log fires during combat. After this fix, it stops firing. Then remove the temporary log.

- [x] **Step 4: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "Freeze player pawn during combat via process_mode toggle"
```

---

### Task 14 — Add a permanent group `player` and make sure it survives instantiation

**What and why:** The `_pawn` instance needs to be discoverable by trigger volumes (which body_entered? is it the player?). Group membership on the .tscn file root carries over to instances, so this is mostly a verification task. Skip if Task 12 step 4 already covered it — but worth confirming that the runtime instance actually belongs to the group.

**Files:** none (verification only)

- [x] **Step 1: Add a temporary diagnostic to GameManager**

In `_load_overworld`, after instantiating the pawn, temporarily add:

```gdscript
    Log.info("Pawn in 'player' group:", _pawn.is_in_group("player"))
```

- [x] **Step 2: Run and check**

F5. Output panel should show:

```
Pawn in 'player' group: true
```

If it says false, go back to Task 12 step 4 and verify the group was actually saved on the .tscn file.

- [x] **Step 3: Remove the diagnostic line**

Delete the `Log.info("Pawn in 'player' group: ...")` line. Save.

- [x] **Step 4: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "Verify player group membership survives runtime instantiation"
```

---

## Phase 6 — Camera Rebinding

Add a `RemoteTransform3D` child to the player pawn. Have GameManager rebind its `remote_path` to the current zone's Camera3D after each zone load. Combat camera switching stays as-is.

### Task 15 — Add `RemoteTransform3D` to overworld_character.tscn

**What and why:** The pawn needs a child node that copies its transform to the zone's camera each frame. `RemoteTransform3D` is Godot's built-in for this. Add it to the character scene so every overworld character (including future NPCs) would carry one — though for NPCs it'd just stay un-bound.

**Files:**
- Modify: `scenes/characters/overworld_character.tscn`

- [ ] **Step 1: Open the character scene**

Open `scenes/characters/overworld_character.tscn` in the Godot editor.

- [ ] **Step 2: Add a RemoteTransform3D child**

With the `overworld_character` root node selected, add a child of type `RemoteTransform3D`. Name it `CameraAnchor`. Leave its `remote_path` empty — it'll be set at runtime by GameManager. Position the anchor at the offset you want from the character (typically `(0, 1.5, 0)` to anchor to chest height rather than feet, but tune to taste).

Save the scene.

- [ ] **Step 3: Run the game**

F5. Nothing should change visually — the `RemoteTransform3D` has no `remote_path` yet, so it's a no-op. The character moves as before; the camera doesn't follow yet.

Output panel: no errors.

- [ ] **Step 4: Commit**

```bash
git add scenes/characters/overworld_character.tscn
git commit -m "Add CameraAnchor (RemoteTransform3D) to overworld_character"
```

---

### Task 16 — Rebind `CameraAnchor.remote_path` per zone load

**What and why:** After a zone is loaded and the pawn is positioned, the camera anchor needs to point at the zone's `System/Camera3D`. Each zone has its own camera (different framing); rebinding per load is the simplest correct answer.

**Files:**
- Modify: `scripts/core/game_manager.gd`

- [ ] **Step 1: Add the rebind step to `_load_overworld`**

In `_load_overworld`, after the pawn position is set and before `exploration.enter()` (or after — order doesn't matter), add:

```gdscript
    var zone_camera: Camera3D = instance.get_node_or_null("System/Camera3D")
    if zone_camera and _pawn:
        var anchor: RemoteTransform3D = _pawn.get_node_or_null("CameraAnchor")
        if anchor:
            anchor.remote_path = anchor.get_path_to(zone_camera)
            Log.info("CameraAnchor bound to:", zone_camera.get_path())
        else:
            Log.warn("CameraAnchor not found on pawn — camera will not follow")
    else:
        Log.warn("Zone has no System/Camera3D, or pawn missing — skipping camera rebind")
```

- [ ] **Step 2: Run the game**

F5. You should see:
- `CameraAnchor bound to: /root/Main/System/Camera3D` (or similar path)
- The camera follows the character as it walks

If the camera looks "snapped" to the character (intersects walls / clips into geometry), that's the camera anchor offset being too close. Tune the `CameraAnchor` transform on `overworld_character.tscn`.

If the camera doesn't follow but no errors appear, double-check that the zone scene actually has `System/Camera3D` (not `CameraRig/Camera3D` or something else). Adjust the path in the `get_node_or_null` call to match your actual scene structure.

- [ ] **Step 3: Verify combat camera switching still works**

Trigger combat. The combat camera should take over (combat scene calls `make_current()` on its own camera). The overworld camera, although still being driven by the RemoteTransform3D, isn't current — so the player doesn't see it. End combat: overworld camera reclaims via the saved `_overworld_camera` reference.

- [ ] **Step 4: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "Rebind CameraAnchor.remote_path to zone's Camera3D on zone load"
```

---

## Phase 7 — TRANSITIONING State, Zone Exits, and Zone-to-Zone Transitions

Add the `TRANSITIONING` state. Author a second test zone. Create the `ZoneExit` scene/script. Add `zone_exit_requested` signal. Wire GameManager to handle zone-to-zone transitions with state guards.

### Task 17 — Add `TRANSITIONING` to the GameState enum

**What and why:** The fourth state. Used as a guard in event handlers to prevent stacked transitions.

**Files:**
- Modify: `autoloads/Enums.gd` (or wherever `GameState` is defined)

- [ ] **Step 1: Locate the GameState enum**

```bash
grep -rn "enum GameState" /home/bart/Projects/neverworld-v-2/
```

It's likely in `autoloads/Enums.gd` or a similar location.

- [ ] **Step 2: Add TRANSITIONING**

Update the enum:

```gdscript
enum GameState {
    MAINMENU,
    OVERWORLD,
    COMBAT,
    TRANSITIONING,
}
```

- [ ] **Step 3: Run the game**

F5. Should run identically — nothing checks for or sets TRANSITIONING yet.

- [ ] **Step 4: Commit**

```bash
git add autoloads/Enums.gd
git commit -m "Add TRANSITIONING state to GameState enum"
```

---

### Task 18 — Set TRANSITIONING during transitions, add guards

**What and why:** Wrap each multi-frame transition (encounter trigger, combat end, future zone load) so `state = TRANSITIONING` while it runs. Handlers that initiate transitions guard on `state == OVERWORLD`. Prevents button-mashing during fades from stacking transitions.

**Files:**
- Modify: `scripts/core/game_manager.gd`

- [ ] **Step 1: Update `_on_encounter_triggered` with TRANSITIONING bookends and BGM pause**

Replace its current body (which Task 3 wrote) with:

```gdscript
func _on_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
    if state != Enums.GameState.OVERWORLD:
        Log.warn("Encounter ignored — game state is", Enums.GameState.keys()[state])
        return
    Log.info("Encounter triggered, transitioning to combat")
    state = Enums.GameState.TRANSITIONING
    _overworld_camera = get_viewport().get_camera_3d()
    var exploration: Exploration = current_overworld.get_node_or_null("Exploration")
    if exploration:
        exploration.pause_for_combat()
    await screen_fader.fade_out()
    _current_combat = CombatSceneTemplate.instantiate()
    add_child(_current_combat)
    _current_combat.initialize(composition, environment, bgm)
    current_overworld.process_mode = Node.PROCESS_MODE_DISABLED
    if _pawn:
        _pawn.process_mode = Node.PROCESS_MODE_DISABLED
    await screen_fader.fade_in()
    state = Enums.GameState.COMBAT
```

- [ ] **Step 2: Update `end_combat` with TRANSITIONING bookends and BGM resume**

```gdscript
func end_combat() -> void:
    if state != Enums.GameState.COMBAT:
        Log.warn("end_combat ignored — game state is", Enums.GameState.keys()[state])
        return
    Log.info("Combat finished, transitioning to overworld")
    state = Enums.GameState.TRANSITIONING
    await screen_fader.fade_out()
    _current_combat.queue_free()
    _current_combat = null
    current_overworld.process_mode = Node.PROCESS_MODE_INHERIT
    if _pawn:
        _pawn.process_mode = Node.PROCESS_MODE_INHERIT
    if _overworld_camera != null:
        _overworld_camera.make_current()
    var exploration: Exploration = current_overworld.get_node_or_null("Exploration")
    if exploration:
        exploration.resume_after_combat()
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
```

- [ ] **Step 3: Run the game**

F5. Trigger combat, end combat. Behaviour should be identical to before, with TRANSITIONING state in between visible only via the state machine. Try mashing the encounter trigger during a fade — it should log a warning "Encounter ignored — game state is TRANSITIONING" and not start a second fade.

- [ ] **Step 4: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "Bookend transitions with TRANSITIONING state, guard handlers against stacking"
```

---

### Task 19 — Create `ZoneExit` scene + script, add `zone_exit_requested` signal

**What and why:** A trigger volume that, when entered by the player, fires a signal to GameManager telling it to load a different zone at a specific spawn point.

**Files:**
- Modify: `autoloads/ExplorationEvents.gd`
- Create: `scripts/exploration/ZoneExit.gd`
- Create: `scenes/exploration/zone_exit.tscn`

- [ ] **Step 1: Add the signal**

In `autoloads/ExplorationEvents.gd`, add:

```gdscript
signal zone_exit_requested(target_zone: PackedScene, target_spawn_point: StringName)
```

- [ ] **Step 2: Create the ZoneExit script**

Create `scripts/exploration/ZoneExit.gd`:

```gdscript
class_name ZoneExit
extends Area3D

@export var target_zone: PackedScene
@export var target_spawn_point: StringName = &"default"

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _exit_tree() -> void:
    if body_entered.is_connected(_on_body_entered):
        body_entered.disconnect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
    if not body.is_in_group("player"):
        return
    if target_zone == null:
        Log.warn("ZoneExit triggered but target_zone is null")
        return
    Log.info("ZoneExit triggered, requesting zone:", target_zone.resource_path, "spawn:", target_spawn_point)
    ExplorationEvents.zone_exit_requested.emit(target_zone, target_spawn_point)
```

- [ ] **Step 3: Create the ZoneExit scene**

Create `scenes/exploration/zone_exit.tscn`. Root: `Area3D` named `ZoneExit`, attach the script. Add a child `CollisionShape3D`. Configure the shape (e.g., `BoxShape3D` with `size = (1, 2, 1)` for a small standable zone). Save.

- [ ] **Step 4: Run the game**

F5. The new files don't change runtime behaviour yet — no ZoneExit instances are placed. Verify no parse errors.

- [ ] **Step 5: Commit**

```bash
git add autoloads/ExplorationEvents.gd scripts/exploration/ZoneExit.gd scenes/exploration/zone_exit.tscn
git commit -m "Add ZoneExit trigger and zone_exit_requested signal"
```

---

### Task 20 — Author a second test zone

**What and why:** To test zone-to-zone transitions, we need a second zone to transition into. Create a minimal zone with the same Zone template structure as `main.tscn`, plus a ZoneExit pointing back to `main.tscn`.

**Files:**
- Create: `scenes/exploration/zones/test_zone_b.tscn`
- Create: `scenes/exploration/zones/test_zone_b_environment.tscn` (geometry)

- [ ] **Step 1: Create the geometry scene**

Create `scenes/exploration/zones/test_zone_b_environment.tscn`. Root: `Node3D` named `TestZoneBEnvironment`. Add a `MeshInstance3D` with a `PlaneMesh` (size 10x10) and a different colour material than main.tscn (e.g., blue) so it's visually distinct. Save.

- [ ] **Step 2: Create the zone scene**

Create `scenes/exploration/zones/test_zone_b.tscn`. Root: `Node` named `TestZoneB`. Build the Zone template:

```
TestZoneB (Node)
├── System
│   ├── WorldEnvironment      ← reuse the same Environment.tres or make a new one
│   └── Camera3D              ← orthographic, current=true, framed on the play area
├── SpawnPoints
│   ├── default (Marker3D)    ← centre of zone
│   └── from_main (Marker3D)  ← position where player appears coming from main.tscn
├── Triggers
│   └── ZoneExit_to_main (instance of zone_exit.tscn)
│       ← target_zone = main.tscn, target_spawn_point = &"from_test_zone_b"
├── Exploration
│   ├── ExplorationEnvironment   ← scene = test_zone_b_environment.tscn
│   └── ExplorationBGM
└── (no Combat for this test zone yet — not needed)
```

Set the `ExplorationEnvironment.scene` export to `test_zone_b_environment.tscn`. Set the `ZoneExit.target_zone` export to `main.tscn`. Set the `ZoneExit.target_spawn_point` to `&"from_test_zone_b"`.

Position the `ZoneExit_to_main` collision somewhere visible/walkable in the zone (e.g., on the edge of the plane).

Save.

- [ ] **Step 3: Add the inverse ZoneExit to main.tscn**

Open `main.tscn`. Under (or as) `Triggers/`, add an instance of `zone_exit.tscn` named `ZoneExit_to_test_zone_b`. Set its `target_zone` to `test_zone_b.tscn` and `target_spawn_point` to `&"from_main"`. Position its collision somewhere walkable.

Add the corresponding spawn point: under `SpawnPoints/`, add a `Marker3D` named `from_test_zone_b` positioned at where the player should appear when returning to main.

Save.

- [ ] **Step 4: Run the game**

F5. Walk into the `ZoneExit_to_test_zone_b` trigger. Output panel should show:

- `ZoneExit triggered, requesting zone: res://scenes/exploration/zones/test_zone_b.tscn spawn: from_main`

Nothing else happens because GameManager doesn't handle the signal yet — that's Task 21.

- [ ] **Step 5: Commit**

```bash
git add scenes/exploration/zones/test_zone_b.tscn scenes/exploration/zones/test_zone_b_environment.tscn main.tscn
git commit -m "Author test_zone_b with ZoneExits in both directions for transition verification"
```

---

### Task 21 — Implement zone-to-zone transition handler in GameManager

**What and why:** Listen for `zone_exit_requested`. Run the same load sequence as `_load_overworld` but with state guarding and using the target_spawn_point name. Refactor `_load_overworld` to take a spawn point name so both flows share the same code path.

**Files:**
- Modify: `scripts/core/game_manager.gd`

- [ ] **Step 1: Refactor `_load_overworld` to accept a spawn point**

Change its signature and use the spawn point inside:

```gdscript
func _load_zone(zone_scene: PackedScene, spawn_point: StringName = &"default") -> void:
    if current_overworld:
        var prev_exploration: Exploration = current_overworld.get_node_or_null("Exploration")
        if prev_exploration:
            prev_exploration.exit()
        current_overworld.queue_free()
        current_overworld = null

    var instance: Node = zone_scene.instantiate()
    current_scene.add_child(instance)
    current_overworld = instance

    if _pawn == null:
        _pawn = OverworldPawnTemplate.instantiate()
        add_child(_pawn)
        Log.info("Overworld pawn instantiated")

    var spawn_points: Node = instance.get_node_or_null("SpawnPoints")
    var marker: Marker3D = null
    if spawn_points:
        marker = spawn_points.get_node_or_null(spawn_point)
    if marker:
        _pawn.global_position = marker.global_position
    else:
        Log.error("Spawn point not found:", spawn_point, "— falling back to Vector3.ZERO")
        _pawn.global_position = Vector3.ZERO

    var zone_camera: Camera3D = instance.get_node_or_null("System/Camera3D")
    if zone_camera and _pawn:
        var anchor: RemoteTransform3D = _pawn.get_node_or_null("CameraAnchor")
        if anchor:
            anchor.remote_path = anchor.get_path_to(zone_camera)

    var exploration: Exploration = instance.get_node_or_null("Exploration")
    if exploration:
        exploration.enter()
```

Delete the old `_load_overworld` function. The new function is named `_load_zone` and accepts a `PackedScene` directly (not a path string) plus a spawn point name.

- [ ] **Step 2: Update `start_new_game` to use the new function**

```gdscript
const InitialZone: PackedScene = preload("res://main.tscn")

func start_new_game() -> void:
    Log.info("New Game selected. Loading...")
    PartyManager.start_new_game()
    state = Enums.GameState.TRANSITIONING
    await screen_fader.fade_out()
    _clear_current_scene()
    _load_zone(InitialZone, &"default")
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
    Log.info("New Game started!")
```

`InitialZone` is a temporary preload — once Phase 8 introduces the Area resource, this becomes a property of the starting Area instead.

- [ ] **Step 3: Add the zone_exit_requested handler**

In `_ready()` of GameManager, add:

```gdscript
    ExplorationEvents.zone_exit_requested.connect(_on_zone_exit_requested)
```

Then add the handler:

```gdscript
func _on_zone_exit_requested(target_zone: PackedScene, target_spawn_point: StringName) -> void:
    if state != Enums.GameState.OVERWORLD:
        Log.warn("Zone exit ignored — game state is", Enums.GameState.keys()[state])
        return
    Log.info("Zone exit accepted, loading:", target_zone.resource_path)
    state = Enums.GameState.TRANSITIONING
    await screen_fader.fade_out()
    _load_zone(target_zone, target_spawn_point)
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
```

- [ ] **Step 4: Run the game**

F5. Walk into the `ZoneExit_to_test_zone_b` trigger. Expected:

- `ZoneExit triggered, requesting zone: res://scenes/exploration/zones/test_zone_b.tscn spawn: from_main`
- `Zone exit accepted, loading: res://scenes/exploration/zones/test_zone_b.tscn`
- Fade out
- New zone loads (blue plane visible)
- Pawn appears at `from_main` Marker3D position
- Camera follows
- Fade in

Walk into the return trigger in test_zone_b. The pawn should transition back to main.tscn at the `from_test_zone_b` spawn point.

If the camera doesn't follow in test_zone_b, the rebind code is finding `System/Camera3D` correctly and should work. Verify the camera node is at that path.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "Wire zone-to-zone transitions via zone_exit_requested handler"
```

---

## Phase 8 — Area Resource

Add the Area resource class. Author a single test Area .tres. Adjust `start_new_game` to load the Area's entry zone instead of hardcoding `main.tscn`.

### Task 22 — Create the `Area` resource class

**What and why:** A pure data class for grouping zones into a logical region. Just exports — no logic.

**Files:**
- Create: `scripts/exploration/Area.gd`

- [ ] **Step 1: Create the script**

Create `scripts/exploration/Area.gd`:

```gdscript
class_name Area
extends Resource

@export var area_name: String
@export var entry_zone: PackedScene
@export var world_map_position: Vector2
# zones: Array[ZoneConnection] — deferred until world map work
```

The `zones` array (zone graph) is deferred to the world map spec — for now, the area just needs to know which zone to load when entered.

- [ ] **Step 2: Create the test Area resource**

In Godot editor, in the FileSystem panel, navigate to (or create) `resources/areas/`. Right-click → New Resource. Pick the `Area` resource type. Save as `test_area.tres`.

```bash
mkdir -p /home/bart/Projects/neverworld-v-2/resources/areas
```

In the Inspector, set:
- `area_name`: "Test Area"
- `entry_zone`: drag `main.tscn` here
- `world_map_position`: leave at (0, 0) for now

Save.

- [ ] **Step 3: Run the game**

F5. The new resource exists but isn't used yet. Verify no parse errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/exploration/Area.gd resources/areas/test_area.tres
git commit -m "Add Area resource class and test_area.tres"
```

---

### Task 23 — Wire `start_new_game` to load via Area

**What and why:** Replace the hardcoded `InitialZone` preload with an Area reference. GameManager reads the Area's `entry_zone` and loads it. Sets the stage for future world-map navigation where the player picks an Area.

**Files:**
- Modify: `scripts/core/game_manager.gd`

- [ ] **Step 1: Replace the InitialZone constant with an InitialArea**

Remove:

```gdscript
const InitialZone: PackedScene = preload("res://main.tscn")
```

Add:

```gdscript
const InitialArea: Area = preload("res://resources/areas/test_area.tres")
```

- [ ] **Step 2: Update `start_new_game` to use the Area**

```gdscript
func start_new_game() -> void:
    Log.info("New Game selected. Loading area:", InitialArea.area_name)
    PartyManager.start_new_game()
    state = Enums.GameState.TRANSITIONING
    await screen_fader.fade_out()
    _clear_current_scene()
    _load_zone(InitialArea.entry_zone, &"default")
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
    Log.info("New Game started!")
```

- [ ] **Step 3: Run the game**

F5. Should see:

- `New Game selected. Loading area: Test Area`
- Same zone load sequence as before
- Game runs identically

If the resource fails to preload, double-check the path and that the .tres file references the Area script via UID (open it with Godot and re-save if needed).

- [ ] **Step 4: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "Load entry zone via InitialArea instead of hardcoded path"
```

---

## What Comes Next

With the architecture in place, the natural next steps are:

- **World map.** Navigate between Areas via a world-map UI. Adds the `zones` array (zone graph) to the Area resource.
- **Zone state persistence.** Flag autoload so chests stay opened, NPCs stay talked-to, between zone visits.
- **Save/load.** Persist `(current_area, current_zone, spawn_point, party_data)` to disk.
- **Scripted encounter wiring.** A `BossTrigger` scene that fires `scripted_encounter_triggered` from inside `Triggers/`. The signal already exists; this just adds the first emitter.
- **NPC content authoring.** `overworld_character.tscn` with `NPCBehaviourComponent` slotted in, placed in `NPCs/`, with dialogue/interaction logic.
- **Renaming `main.tscn`.** Eventually retire the test name in favour of `northern_forest_forest_path.tscn` or similar — a small migration once you have a real area named.

Each of these is its own spec and plan. The architecture is now ready to host them.
