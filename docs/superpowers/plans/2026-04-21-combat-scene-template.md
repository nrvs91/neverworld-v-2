# Combat Scene Template — Implementation Plan

> This plan is written for you to implement yourself. Each task explains what to build and why. When something is unclear, ask.

> **No automated tests in this project.** Verification steps mean: open Godot, run the scene (F5), check the Output panel for `Log.*` messages and errors.

**Goal:** Give the combat scene a proper spatial layout (slot positions, camera, framing anchors), make both spawners work identically (ephemeral), and wire the camera switch so combat is actually visible when it triggers.

**Architecture:** `CombatScene` stays as a permanent disabled child of `GameManager` — no structural change. We're adding a `Camera3D` to the scene, authoring slot positions in the editor, and rewriting `PlayerSpawner` to match `EnemySpawner`'s spawn/clear pattern. GameManager saves the overworld camera reference before switching to combat, then restores it on return.

**Spec:** `docs/superpowers/specs/2026-04-21-combat-scene-template-design.md`

**Tech Stack:** Godot 4.6, GDScript only. Use `Log.*` not `print()`.

---

## File Map

```
scripts/combat/PlayerSpawner.gd        MODIFY — rewrite to ephemeral (mirrors EnemySpawner)
scenes/combat/components/player_spawner.tscn  MODIFY — remove pre-placed CombatCharacters from slots
scripts/combat/CombatCharacter.gd      MODIFY — remove reset_for_combat() (dead code)
scripts/combat/EnemySpawner.gd         MODIFY — add Log.info to initialize() for consistency
scripts/combat/CombatScene.gd          MODIFY — add camera.make_current(), add cleanup(), clear on init
scenes/combat/combat_scene.tscn        MODIFY — add Camera3D, CameraTargets, placeholder floor
scripts/core/game_manager.gd           MODIFY — save/restore overworld camera, call cleanup()
```

---

## Task 1 — Make PlayerSpawner Ephemeral

**What and why:** Right now `PlayerSpawner` holds permanent `CombatCharacter` nodes as pre-placed children of each slot. That's different from `EnemySpawner`, which spawns and frees characters per encounter. We're making both work the same way: spawn on encounter start, free on encounter end. Fresh node = guaranteed fresh state, no reset logic, no risk of lingering data.

**In Godot, `queue_free()`** schedules a node for deletion at the end of the current frame — it doesn't vanish immediately, which is why you can safely call it inside a loop. `add_child()` adds a node to the scene tree; without it, the node exists in memory but Godot doesn't know about it.

**Files:** Modify `scripts/combat/PlayerSpawner.gd`, modify `scenes/combat/components/player_spawner.tscn`, modify `scripts/combat/CombatCharacter.gd`

- [x] Open `scripts/combat/PlayerSpawner.gd`. Replace its entire contents with:

```gdscript
class_name PlayerSpawner
extends Node

const CombatCharacterScene = preload("res://scenes/combat/combat_character.tscn")

func initialize() -> void:
    clear()
    var slots := get_children()
    for i in slots.size():
        var slot_data: Dictionary = PartyManager.get_slot(i)
        if slot_data.is_empty():
            continue
        var character: CombatCharacter = CombatCharacterScene.instantiate()
        slots[i].add_child(character)
        character.initialize_player(slot_data["player_data"], slot_data["save_data"])
    Log.info("PlayerSpawner initialized")

func clear() -> void:
    for slot in get_children():
        for child in slot.get_children():
            child.queue_free()
    Log.info("PlayerSpawner cleared")
```

This is now identical in structure to `EnemySpawner`. `initialize()` always calls `clear()` first so it's safe to call multiple times.

- [x] Open `scenes/combat/components/player_spawner.tscn` in the Godot editor. Each slot node (`Slot1`, `Slot2`, `Slot3`) currently has a `CombatCharacter` as a child. **Delete those CombatCharacter instances** — leave only the bare slot `Node3D` nodes. The slots stay; the characters inside them go.

- [x] Open `scripts/combat/CombatCharacter.gd`. Remove the `reset_for_combat()` method entirely — it's no longer called by anything:

```gdscript
# DELETE this method:
func reset_for_combat() -> void:
    tokens.flush()
    Log.info("Active tokens flushed.")
```

- [x] Open `scripts/combat/EnemySpawner.gd`. Add a log line at the end of `initialize()` so both spawners are consistent:

```gdscript
func initialize(composition: CombatConfig) -> void:
    clear()
    # ... existing spawn logic stays exactly as-is ...
    Log.info("EnemySpawner initialized")  # add this line at the end
```

- [x] Run the game (F5). Walk until an encounter triggers. In the Output panel you should see:
  - `PlayerSpawner cleared` then `PlayerSpawner initialized`
  - `EnemySpawner cleared` then `EnemySpawner initialized`
  - No errors about missing children or null references

  If PartyManager has no party data yet, you'll see no character init lines for players — that's expected.

  **Note on subsequent encounters:** On the second encounter onwards, `PlayerSpawner cleared` will appear **twice** — once from `cleanup()` at end of combat, and again from the internal `clear()` inside `initialize()`. That's intentional — `initialize()` always clears first so it's safe to call even if cleanup wasn't called. The double log is normal, not a bug.

- [x] Commit:
```bash
git add scripts/combat/PlayerSpawner.gd scenes/combat/components/player_spawner.tscn scripts/combat/CombatCharacter.gd
git commit -m "Make PlayerSpawner ephemeral: spawn/clear per encounter, mirrors EnemySpawner"
```

---

## Task 2 — Add Camera3D and Wire the Switch

**What and why:** When the combat scene is enabled, Godot keeps rendering through whatever camera was active last — the overworld camera. We need to add a `Camera3D` to the combat scene and call `make_current()` on it when combat starts, so Godot knows to switch. On `end_combat()`, we restore the overworld camera.

**How Godot cameras work:** In Godot 4, exactly one `Camera3D` is "current" per viewport at a time. `make_current()` tells Godot "render through me now." It doesn't matter which node calls it or where in the tree the camera lives. Disabling a node with `process_mode = DISABLED` does NOT automatically un-current its camera — you have to explicitly switch.

**Files:** Modify `scripts/combat/CombatScene.gd`, modify `scripts/core/game_manager.gd`, modify `scenes/combat/combat_scene.tscn`

- [x] **Editor first:** Open `scenes/combat/combat_scene.tscn` in the Godot editor. Add a `Camera3D` node as a direct child of the root `CombatScene` node, named `Camera3D`. Set `Projection` to `Orthographic` and `Size` to `3.0`. Leave position and rotation at defaults for now — Task 3 sets the final values. Save the scene.

  **Do this before touching any script.** The script you're about to write references `$Camera3D` via `@onready` — if that node doesn't exist in the scene when the game runs, Godot throws a null reference error.

- [x] Open `scripts/combat/CombatScene.gd`. Rewrite it:

```gdscript
class_name CombatScene
extends Node

@onready var camera: Camera3D = $Camera3D
@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer

func initialize(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
    camera.make_current()
    _clear_environment()
    player_spawner.initialize()
    enemy_spawner.initialize(composition)
    if environment:
        environment_mount.add_child(environment.instantiate())
    if bgm:
        bgm_player.stream = bgm
        bgm_player.play()
    Log.info("CombatScene initialized")

func cleanup() -> void:
    player_spawner.clear()
    enemy_spawner.clear()
    bgm_player.stop()
    _clear_environment()
    Log.info("CombatScene cleaned up")

func _clear_environment() -> void:
    for child in environment_mount.get_children():
        child.queue_free()
```

Note: `player_spawner.initialize()` already calls `clear()` internally, so the old `reset_characters()` call is gone. `cleanup()` is the new method GameManager will call at end of combat.

- [x] Open `scripts/core/game_manager.gd`. Add a variable to store the overworld camera. Place it next to the existing `var current_overworld: Node = null` line — keep related state together:

```gdscript
var current_overworld: Node = null    # already exists
var _overworld_camera: Camera3D = null  # add this line right below it
```

- [x] In `_on_encounter_triggered()`, save the current camera before switching. Add this line **before** `combat_scene.process_mode = Node.PROCESS_MODE_INHERIT`:

```gdscript
_overworld_camera = get_viewport().get_camera_3d()
```

`get_viewport().get_camera_3d()` returns whichever camera is currently active. At the moment combat triggers, that's the overworld camera — so we save it here.

- [x] In `end_combat()`, call cleanup and restore the camera. Rewrite `end_combat()`:

```gdscript
func end_combat() -> void:
    Log.info("Combat finished, transitioning to overworld")
    await screen_fader.fade_out()
    combat_scene.cleanup()
    combat_scene.process_mode = Node.PROCESS_MODE_DISABLED
    current_overworld.process_mode = Node.PROCESS_MODE_INHERIT
    if _overworld_camera:
        _overworld_camera.make_current()
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
```

- [x] Run the game (F5). Trigger an encounter. The screen should no longer go to a black void — you'll be looking through the combat camera, which currently frames the origin. It'll look empty (no floor yet, slots at origin), but **no black screen** means the camera switch worked.

  Check the Output panel for `CombatScene initialized` and no errors.

- [x] Commit:
```bash
git add scripts/combat/CombatScene.gd scripts/core/game_manager.gd scenes/combat/combat_scene.tscn
git commit -m "Add Camera3D to CombatScene, wire make_current() on combat start and restore on end"
```

---

## Task 3 — Author the Stage Layout

**What and why:** Slot positions are currently all at the origin (0, 0, 0) — everyone spawns on top of each other. We need to spread them out to match the layout from the mockup: players lower-left, enemies upper-right, along a diagonal axis. We also add static framing anchors for the future camera controller and a placeholder floor so the scene looks like something.

**How isometric coordinates work:** In Godot's 3D with an isometric orthographic camera (looking roughly "south-west"), what appears "lower on screen" is further along the positive Z axis, and "left on screen" is further along the negative X axis. So:
- Players (lower-left on screen) → negative X, positive Z in world space
- Enemies (upper-right on screen) → positive X, negative Z in world space

You'll tune these visually in the editor — these are starting points, not exact values.

**Files:** Modify `scenes/combat/combat_scene.tscn` (editor work — no script changes)

- [x] Open `scenes/combat/combat_scene.tscn` in the Godot editor. Select the `PlayerSpawner` node and expand it. You'll see `Slot1`, `Slot2`, `Slot3` as children (the bare Node3Ds from Task 1).

  Position the three player slots. Suggested starting values — adjust visually:
  - `Slot1`: position `(-1.5, 0, 2.0)` — center-left, closest to camera
  - `Slot2`: position `(-3.0, 0, 2.5)` — further left, slightly deeper
  - `Slot3`: position `(-1.5, 0, 3.5)` — behind Slot1, staggered

  The goal is a loose triangle that reads as "a party standing together."

- [x] Now select `EnemySpawner` and position its six slots. Suggested starting values:
  - `Slot1`: position `(1.0, 0, -1.0)`
  - `Slot2`: position `(2.5, 0, -0.5)`
  - `Slot3`: position `(3.5, 0, -2.0)`
  - `Slot4`: position `(1.5, 0, -3.0)`
  - `Slot5`: position `(3.0, 0, -3.5)`
  - `Slot6`: position `(4.5, 0, -1.5)`

  Six positions spread across the upper-right. Not a perfect grid — a loose cluster feels more natural.

- [x] Now add the `CameraTargets` node. In the scene tree, add a plain `Node` as a direct child of the root, named `CameraTargets`. Inside it, add three `Node3D` children:
  - `PlayerSide` — position near the center of the player cluster, roughly `(-2.0, 1.0, 2.5)`
  - `Center` — midpoint between both groups, roughly `(1.0, 1.0, 0.0)`
  - `EnemySide` — near the center of the enemy cluster, roughly `(2.5, 1.0, -2.0)`

  The Y = 1.0 lifts the target to chest height — more natural for camera focus than ground level.

  These nodes do nothing right now. They're landmarks the future camera controller will aim at.

- [x] Add a placeholder floor. In the scene tree, add a `CSGBox3D` node as a direct child of root, named `FloorPlaceholder`. In the Inspector:
  - Size: `(12.0, 0.2, 12.0)` — wide flat box covering the whole arena
  - Position: `(1.0, -0.1, 0.0)` — centered roughly between both parties, slightly below Y=0

  This won't look pretty — it just confirms the camera is aimed correctly and gives something to see.

- [x] Position the `Camera3D`. With the slots and floor placed, move the camera to frame the whole battlefield. As a starting point: position `(-1.0, 8.0, 6.0)`, rotation `(-35, -20, 0)` (degrees). This is a rough isometric angle — adjust in the editor until all 9 slots are visible with comfortable padding.

  **Tip:** In the Godot editor, with the Camera3D selected, click "Preview" in the top-left of the viewport to see exactly what the camera sees. Drag it around until the layout looks right.

- [x] Run the game (F5). Trigger an encounter. You should now see:
  - The placeholder floor visible
  - At least one enemy character appearing at a slot position (if your test CombatConfig has an enemy)
  - Player slots empty (PartyManager has no data) — expected
  - The camera framing the arena
  - `CombatScene initialized` in the log

- [x] Commit:
```bash
git add scenes/combat/combat_scene.tscn
git commit -m "Author combat stage: slot positions, Camera3D framing, CameraTargets, placeholder floor"
```

---

## Task 4 — End-to-End Verification

**What to verify:**

- [x] Run the game (F5) with `Globals.dev_mode = true` (skip menu). Walk the character. After the StepCounter threshold:
  - `StepCounter threshold reached` appears
  - `EncounterPool picked: ...` appears
  - `Encounter triggered, transitioning to combat` appears
  - Screen fades out then back in
  - **Combat camera is active** — you see the battlefield, not a black screen
  - `PlayerSpawner cleared` and `PlayerSpawner initialized` appear
  - `EnemySpawner cleared` and enemy init lines appear (if test CombatConfig has enemies)
  - `CombatScene initialized` appears

- [x] Verify slot positions look right. If slots are bunched or off-screen, go back to the editor and adjust position values. Press F5 again and retrigger combat to check.

- [x] Test `end_combat()`. In `game_manager.gd`, temporarily add a debug key to trigger it — or call it from the F1 debug trigger if you wired that. Confirm:
  - Screen fades out
  - `CombatScene cleaned up` appears in log
  - Overworld camera resumes — you're back in the overworld
  - Walking again after returning still works (StepCounter still fires)

- [x] Final commit if anything was tweaked:
```bash
git add .
git commit -m "Combat scene template: verified end-to-end camera switch and slot layout"
```

---

## What Comes Next

With the stage in place, the natural next steps are:

- **CombatVisuals** — `CombatVisuals.gd` already exists as a stub. The next plan fleshes out `approach()`, `recover()`, and the animation beat API from `docs/superpowers/specs/2026-04-13-combat-visuals-design.md`
- **PartyManager data** — author a `PlayerData.tres` for Skugge so PlayerSpawner has something to spawn
- **Camera controller** — a future spec will animate the camera between `CameraTargets` and character positions during actions
