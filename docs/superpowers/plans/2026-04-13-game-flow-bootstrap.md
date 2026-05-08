# Game Flow & Bootstrap — Implementation Plan

> This is a companion to the combat-transition plan. Tasks 5–17 over there still apply — this doc adds the boot/menu/flow layer and reworks GameManager into its proper role. The combat-transition plan's Task 15 (GameManager) and Task 16 (autoload registration + test map) should be replaced by the tasks in this document.

> Same rule: each task tells you what and why. You write the code. Ask if stuck.

## The Flow, Start to Finish

```
[Godot loads main scene: game_manager.tscn]
     |
     v
GameManager._ready()
     |
     |-- Globals.skip_to_overworld == true?
     |       |
     |      YES: _start_new_game()  (dev shortcut)
     |       |
     |      NO:  _show_main_menu()
     |                  |
     |            [player presses New Game]
     |                  |
     |            _start_new_game()
     |                  |
     v                  v
PartyManager.start_new_game()
     |
     v
fade_out -> mount overworld scene -> fade_in
     |
     v
[OVERWORLD STATE]
     |                                |
  player walks                   debug F1 key
  StepCounter ticks                   |
     |                                |
  encounter_triggered <----------- CombatEvents bus
     |
     v
fade_out -> freeze overworld -> enable CombatScene -> fade_in
     |
     v
[COMBAT STATE]
     |
  combat resolves (later task)
     |
     v
end_combat()
     |
     v
fade_out -> disable CombatScene -> unfreeze overworld -> fade_in
     |
     v
[OVERWORLD STATE] (loop)
```

## What Changes From the Combat-Transition Plan

The original plan had GameManager as two-state (OVERWORLD/COMBAT) that just freezes/unfreezes an overworld that's always in the tree. That works for testing but doesn't scale to a real game flow. Here's what's different:

1. **Three states** instead of two: MENU, OVERWORLD, COMBAT
2. **GameManager mounts/unmounts scenes** — MainMenu and the overworld are instanced at runtime, not always in the tree
3. **CombatScene stays as a composed child** of the autoload (always present, disabled/enabled) — this is fine, it's small when disabled
4. **map_test.gd's self-registration** (`GameManager.current_overworld = self`) still works — it's the overworld's responsibility to tell GM who it is
5. **Globals.skip_to_overworld** — a toggle for dev mode that bypasses the menu entirely

## Scene Tree (at runtime, overworld state)

```
Root
 +-- ExplorationEvents (autoload)
 +-- CombatEvents (autoload)
 +-- PartyManager (autoload)
 +-- GameManager (autoload, main scene)
      +-- ScreenFader (CanvasLayer, always present)
      +-- CombatScene (Node, disabled until combat)
      +-- CurrentScene (Node, swap holder)
      |    +-- [MainMenu OR Map_XYZ instance]
```

GameManager doesn't care what the current scene *is*. It knows three states and three transitions. That's it.

---

## Task A — Update Globals with dev toggle

**What:** Add a single flag to `Globals.gd` that lets you skip straight to the overworld during development. In a shipped game, this is `false` and the menu shows.

**File:** Modify `scripts/core/Globals.gd`

**What to add:**

```gdscript
@export var skip_to_overworld := true
```

That's it. One export. You set it in the editor inspector on the Globals node. When `true`, GameManager skips the menu. When `false`, it shows the menu normally.

- [x] Add the export to Globals.gd
- [x] Verify in the editor that the property appears in the Globals inspector

---

## Task B — MainMenu scene

**What:** A barebones title screen. For now it just has a "New Game" button. No Continue, no Options — those come later. The button calls `GameManager.start_new_game()`.

**Why a scene, not code inside GameManager:** The menu is UI. It has art, animations, layout. It'll grow. Making it a scene means you can iterate on it in the editor without touching any logic code. And when it's not on screen, it's not in the tree — no wasted frames.

**Files:**
- Create: `scripts/ui/MainMenu.gd`
- Create: `scenes/ui/MainMenu.tscn`

**What the script does:**

`MainMenu.gd` — extends `Control` (or `CanvasLayer`, your call), has one method:

```gdscript
func _on_new_game_pressed() -> void:
    GameManager.start_new_game()
```

The scene is a `Control` (or `CanvasLayer`) with:
- A "New Game" button centered on screen
- Wire the button's `pressed` signal to the script method

That's it. No title art, no animation. A button and a callback. You'll add the rest later.

- [x] Create `scripts/ui/MainMenu.gd`
- [x] Create `scenes/ui/MainMenu.tscn` — Control or CanvasLayer root, centered button, signal wired
- [x] Run the game with `skip_to_overworld = true`. Menu shouldn't appear (GM skips it). Verify this works *before* implementing the menu branch.

---

## Task C — Rework GameManager into the full FSM

**What:** This replaces the Task 15 from the combat-transition plan. GameManager becomes the bootstrapper: it mounts/unmounts scenes, manages three states, and owns the transition animations.

**The key insight:** GameManager is an autoload scene. Its `.tscn` file has ScreenFader and CombatScene as pre-placed children. MainMenu and the overworld map are mounted at runtime into a `CurrentScene` holder node. When transitioning, GM swaps what's in that holder.

**File:** Create `scripts/core/GameManager.gd`, create/modify `scenes/core/game_manager.tscn`

**What the script looks like — read through this, then write it yourself:**

Three states: MENU, OVERWORLD, COMBAT.

`_ready()`:
- Connect to `CombatEvents.encounter_triggered`
- Disable CombatScene (`process_mode = DISABLED`)
- Check `Globals.skip_to_overworld`:
  - If true: call `_start_new_game()`
  - If false: call `_show_main_menu()`

`_show_main_menu()`:
- Instance `MainMenu.tscn`, add as child of the CurrentScene holder
- Set state to MENU

`start_new_game()` — this is public because MainMenu calls it:
- `PartyManager.start_new_game()`
- `await fader.fade_out()`
- `_clear_current_scene()`
- `_load_overworld("res://scenes/overworld/Map_Test.tscn")` — for now hardcode, later the save system tells you which map
- `await fader.fade_in()`
- Set state to OVERWORLD

`_load_overworld(path)`:
- Instance the PackedScene
- Add as child of CurrentScene holder
- The overworld's `_enter_tree` will self-register via `GameManager.current_overworld = self`

`_on_encounter_triggered(composition, environment_scene, bgm_stream)`:
- Guard: only if state == OVERWORLD
- Set state to COMBAT
- Freeze overworld (`process_mode = DISABLED`)
- `await fader.fade_out()`
- Enable CombatScene, call `combat_scene.initialize(...)`
- `await fader.fade_in()`

`end_combat()`:
- `await fader.fade_out()`
- Disable CombatScene
- Unfreeze overworld (`process_mode = INHERIT`)
- `await fader.fade_in()`
- Set state to OVERWORLD

`_clear_current_scene()`:
- For each child of CurrentScene holder: `queue_free()`

**Debug hotkey:** keep the F1 debug trigger from the original plan. If state is OVERWORLD (or MENU?), emit `CombatEvents.encounter_triggered` with a blank CombatConfig.

**The .tscn file** should have this structure:
```
GameManager (Node, script: GameManager.gd)
 +-- ScreenFader (instanced from ScreenFader.tscn)
 +-- CombatScene (instanced from CombatScene.tscn, process_mode: Disabled)
 +-- CurrentScene (Node — empty holder, scenes get mounted here)
```

**`current_overworld`** — this is still needed. The overworld scene self-registers in its `_enter_tree`. GM uses it to freeze/unfreeze. The registration pattern from the original plan (`map_test.gd`) still works.

- [x] Create `scripts/core/GameManager.gd`
- [x] Create/modify `scenes/core/game_manager.tscn` — ScreenFader + CombatScene + CurrentScene holder
- [x] Add `debug_trigger_combat` input action (F1) in Project Settings if not already done
- [x] Test with `skip_to_overworld = true`: game should go straight to overworld, no menu
- [x] Test with `skip_to_overworld = false`: game should show MainMenu, New Game button should transition to overworld

---

## Task D — Register GameManager as autoload (replaces Task 16)

**What:** GameManager is the main scene AND an autoload. It's always in the tree from frame 1.

- [x] Register `GameManager` in `Project → Project Settings → Autoload`:
  - Path: `res://scenes/core/game_manager.tscn`, name: `GameManager`
  - **No `class_name`** — same rule as event buses, autoload name already puts it in global scope
  
- [x] Set `game_manager.tscn` as the **main scene** in `Project → Project Settings → Application → Run → Main Scene`
  - This replaces `Map_Test.tscn` as the main scene
  - `Map_Test.tscn` is now loaded by GameManager when transitioning to overworld

- [x] Autoload order matters:
  1. Globals
  2. ExplorationEvents
  3. CombatEvents
  4. PartyManager
  5. GameManager (last, so everything else exists when its `_ready` fires)

- [x] Verify no errors on launch. All autoloads log ready.

---

## How This Connects to Tasks 5–14 in the Combat-Transition Plan

Tasks 5–14 (EncounterPool through ScreenFader) don't change — they're still valid. Build them in order.

Task 15 (GameManager) is **replaced by Task C** above. Use the three-state version.

Task 16 (autoload + test map) is **replaced by Task D** above. The test map wiring changes:

- `Map_Test.tscn` is no longer the main scene — it's loaded by GameManager
- `map_test.gd`'s self-registration (`GameManager.current_overworld = self`) still works, no changes needed there
- The F1 debug hotkey moves into GameManager

Task 17 (end-to-end verification) still applies, but now the test flow is:

1. **Dev mode** (`skip_to_overworld = true`): game launches straight to overworld. Walk around, encounter triggers, combat loads, debug key works. Same as before.
2. **Menu mode** (`skip_to_overworld = false`): game shows MainMenu first. Press New Game, fades to overworld. Walk around, encounter triggers, etc.

Test both.

---

## Minimal Scene Authoring for Map_Test

When you build the test map (original Task 16), you still need:

- An `EncounterManager` instance with StepCounter, EncounterPool, CombatEnvironment, CombatBGM children
- A `CombatConfig` `.tres` and `EncounterPoolEntry` `.tres` 
- The overworld player character in the scene

Nothing changes about this — just remember that Map_Test is loaded *by* GameManager, not *as* the main scene.