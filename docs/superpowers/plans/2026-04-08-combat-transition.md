# Combat Scene Transition & Data Flow — Implementation Plan

> **Note:** This plan is written for you to implement yourself. Each task explains what to build, why it exists, and what it should look like — you write the code. When something is unclear or you get stuck, ask and we'll work through it together. That's the whole point.

> **No automated tests in this project.** Verification steps mean: open Godot, run the scene (F5), check the Output panel for `Log.*` messages and errors.

**Goal:** Wire the full overworld → combat transition pipe so that walking around (or pressing a debug key) triggers a fade to the combat scene, where combatants spawn at authored positions and print their names and HP/MP to the console.

**Architecture:** Four autoloads handle global concerns (GameManager FSM, PartyManager, two event buses). The combat scene is a permanent child of GameManager — always in the tree, disabled when not active, composed of focused sub-nodes. EncounterManager on each map is a thin coordinator between four component children: a StepCounter, an EncounterPool (weighted `CombatConfig` picker), a CombatEnvironment (the 3D scene to instance for combat), and a CombatBGM (the audio stream to play). On encounter trigger, the manager emits `(composition, environment_scene, bgm_stream)` — three pieces of data, three args.

**Spec:** `docs/superpowers/specs/2026-04-08-combat-transition-design.md`

**Tech Stack:** Godot 4.6, GDScript only. No C#. Use `Log.*` not `print()`.

---

## File Map

Files to create or modify, grouped by concern:

```
# Data resources
scripts/core/Save/GlobalSaveData.gd        NEW — save file root: party slots + character saves
scripts/combat/CombatConfig.gd              NEW — enemy composition for one encounter: six named slots
scripts/combat/EncounterPoolEntry.gd        NEW — pairs a CombatConfig with a pool weight
scripts/characters/PlayerData.gd            MODIFY — add starting_level: int = 1

# Autoloads / event buses
scripts/exploration/ExplorationEvents.gd   NEW — exploration domain signals (step_taken(who: Node3D))
scripts/combat/CombatEvents.gd              NEW — combat domain signals (encounter_triggered)
scripts/autoloads/PartyManager.gd           NEW — holds GlobalSaveData, exposes party slots
exploration_events.tscn                     NEW — autoload scene (at project root)
combat_events.tscn                           NEW — autoload scene (at project root)
scenes/autoloads/PartyManager.tscn          NEW

# Overworld / encounter trigger
scripts/characters/overworld/MovementComponent.gd   MODIFY — emit step_taken(who) via ExplorationEvents
scripts/characters/overworld/StepCounter.gd  NEW — counts steps, emits threshold_reached; lives in overworld scene
scripts/overworld/EncounterPool.gd          NEW — weighted random pick via EncounterPoolEntry resources
scripts/overworld/CombatEnvironment.gd      NEW — data holder: PackedScene for the 3D combat environment
scripts/overworld/CombatBGM.gd              NEW — data holder: AudioStream for the combat BGM
scripts/overworld/EncounterManager.gd       NEW — thin connector: StepCounter + EncounterPool + CombatEnvironment + CombatBGM
scenes/overworld/EncounterPool.tscn         NEW
scenes/overworld/CombatEnvironment.tscn     NEW
scenes/overworld/CombatBGM.tscn             NEW
scenes/overworld/EncounterManager.tscn      NEW

# Combat character
scripts/combat/VitalsComponent.gd           NEW — cur_hp, cur_mp, cur_ap + setup/reset
scripts/combat/TokenContainer.gd            NEW — stub (empty for now)
scripts/combat/CombatInputComponent.gd      NEW — stub (empty for now)
scripts/characters/VisualComponent.gd             MODIFY — make controller optional, add setup()
scenes/combat/components/VitalsComponent.tscn     NEW
scenes/combat/components/TokenContainer.tscn      NEW
scenes/combat/components/CombatInputComponent.tscn NEW
scenes/combat/CombatCharacter.tscn          NEW — assembles all components

# Combat scene
scripts/combat/PlayerSpawner.gd             NEW — owns player slots, inits permanent combat_characters
scripts/combat/EnemySpawner.gd              NEW — owns enemy slots, spawns/frees per encounter
scripts/combat/CombatScene.gd               NEW — thin coordinator: mounts env, starts BGM, calls spawners
scenes/combat/PlayerSpawner.tscn            NEW
scenes/combat/EnemySpawner.tscn             NEW
scenes/combat/CombatScene.tscn              NEW — root holds EnvironmentMount (Node3D) + BGMPlayer (AudioStreamPlayer)

# Core / GameManager
scripts/core/ScreenFader.gd                 NEW — fade_out / fade_in, awaitable
scripts/core/GameManager.gd                 NEW — FSM: OVERWORLD / COMBAT states
scenes/core/ScreenFader.tscn                NEW
scenes/core/game_manager.tscn               MODIFY — add ScreenFader + CombatScene as children
```

---

## Task 1 — GlobalSaveData + CombatConfig + EncounterPoolEntry resources ✅

**What these are:** Three `Resource` subclasses that hold authored data.
- `GlobalSaveData` is the save file root — it knows which characters are in the party and what their current stats are.
- `CombatConfig` defines one encounter's **enemy composition** — which enemies appear in which of the six slots. Nothing else. Environment and BGM are area-level concerns, not per-encounter, so they live elsewhere.
- `EncounterPoolEntry` is the tiny glue resource that pairs a `CombatConfig` with its pool weight. One entry per encounter per pool. Authored in the inspector.

**Files:**
- Create: `scripts/characters/GlobalSaveData.gd`
- Create: `scripts/combat/CombatConfig.gd`
- Create: `scripts/combat/EncounterPoolEntry.gd`

**In Godot, a Resource subclass** is a script that extends `Resource`. You can save instances as `.tres` files in the editor and attach them as exports. Think of `.tres` files as your game's data spreadsheets.

- [x] Create `scripts/core/Save/GlobalSaveData.gd`:

```gdscript
class_name GlobalSaveData
extends Resource

# Active party: 3 character_IDs ordered by slot index (0, 1, 2).
# Empty slot = "". Always exactly 3 entries.
@export var party_slots: Array[String] = ["", "", ""]

# Everyone the player has met or recruited — active party members and bench.
# Keyed by character_ID. A character is added here via PartyManager.recruit()
# the first time they join; their save data persists here forever after.
# TODO: populate this when the recruitment/meeting system is implemented.
@export var roster: Dictionary[String, CharacterSaveData] = {}
```

- [x] Create `scripts/combat/CombatConfig.gd`:

```gdscript
class_name CombatConfig
extends Resource

# Enemy composition for one encounter.
# Each slot corresponds to a spawn position in EnemySpawner (slot1..slot6).
# Any slot may be left null — not every fight has six enemies.

@export var enemy_slot1: EnemyData
@export var enemy_slot2: EnemyData
@export var enemy_slot3: EnemyData
@export var enemy_slot4: EnemyData
@export var enemy_slot5: EnemyData
@export var enemy_slot6: EnemyData
```

- [x] Create `scripts/combat/EncounterPoolEntry.gd`:

```gdscript
class_name EncounterPoolEntry
extends Resource

# One entry in an EncounterPool: a specific enemy composition paired with
# the relative weight used for weighted random picking.
# Higher weight = more common. Not a percentage — just relative to other entries.

@export var composition: CombatConfig
@export var weight: int = 10
```

- [x] Open Godot editor. Verify all three scripts appear without errors in the Script editor (no red underlines).

- [ ] Commit:
```bash
git add scripts/characters/GlobalSaveData.gd scripts/combat/CombatConfig.gd scripts/combat/EncounterPoolEntry.gd
git commit -m "Add GlobalSaveData, CombatConfig, EncounterPoolEntry resource classes"
```

---

## Task 2 — Event buses: ExplorationEvents + CombatEvents ✅ (with caveats)

**What these are:** Autoloads that hold only signal declarations — no logic, no state. Any node anywhere in the game can emit or connect to these. They keep systems decoupled: `MovementComponent` doesn't know about `StepCounter`; it just emits a signal into the void.

**In Godot, autoloads** are nodes that are always present in the scene tree, accessible by their registered name from any script. You register them in `Project → Project Settings → Autoload`.

**⚠️ Caveat — no `class_name` on autoloads:** Godot autoload names live in the same global namespace as `class_name`. If an autoload is named `ExplorationEvents` and the script also declares `class_name ExplorationEvents`, the two collide. Solution: **drop `class_name` from autoload event bus scripts.** Autoloads are already globally accessible by their registered name; `class_name` is redundant and causes the collision. This is now the project convention: autoload event buses have no `class_name`.

**⚠️ Caveat — `step_taken` carries `who: Node3D`:** The signal was changed from `signal step_taken` to `signal step_taken(who: Node3D)`. This allows subscribers (like StepCounter) to filter by who stepped — e.g., only counting player steps, not NPC steps. The emitter passes `get_parent()` (the overworld_character node). See Task 4 for the subscriber side.

- [x] Create `scripts/exploration/ExplorationEvents.gd`:

```gdscript
extends Node

signal step_taken(who: Node3D)
```

- [x] Create `scripts/combat/CombatEvents.gd`:

```gdscript
extends Node

# Fired by EncounterManager when a random encounter should start.
# Carries the three pieces of data needed to initialize CombatScene:
#   - composition: which enemies appear, in which slots
#   - environment: the 3D scene to instance as the combat backdrop
#   - bgm:         the audio stream to play during the fight
# Any of the last two may be null (e.g. for the debug F1 hotkey).
signal encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
```

- [x] Create matching `.tscn` files — placed at project root (not `scenes/autoloads/`, which didn't exist). And that's fine — convention can be tightened later.
  - `exploration_events.tscn`: `Node` root named `ExplorationEvents`, script attached
  - `combat_events.tscn`: `Node` root named `CombatEvents`, script attached

- [x] Register both in `Project → Project Settings → Autoload`:
  - Path: `res://exploration_events.tscn`, Node Name: `ExplorationEvents`
  - Path: `res://combat_events.tscn`, Node Name: `CombatEvents`
  - **Note:** Autoload names use PascalCase (no underscores). If Godot's editor inserts underscores, re-register manually.

- [x] Run the game (F5). No errors. Autoloads visible in remote scene tree.

*Note: Initial commit used `class_name` on both, which caused a "Cannot find member" error. `class_name` was removed in a follow-up and autoload names were changed from `Exploration_Events`/`Combat_Events` to `ExplorationEvents`/`CombatEvents`.*

---

## Task 3 — MovementComponent: emit step_taken ✅

**What changes:** `MovementComponent` now accumulates distance traveled and emits `ExplorationEvents.step_taken(who)` every `step_distance` units. This is the heartbeat that the encounter system listens to.

**Why distance, not time:** A step counter based on time would tick even when standing still. Distance means "you actually walked somewhere." It also naturally maps to footstep audio and VFX later.

**Why `who: Node3D`:** The signal carries the character that stepped, so subscribers can filter (e.g., StepCounter only counts player steps, not NPC steps). The emitter passes `get_parent()` — the overworld_character node.

**File:** Modified `scripts/characters/overworld/MovementComponent.gd`

- [x] Add `step_distance` export, `_distance_accumulated`, and `_steps_taken` private variables:

```gdscript
@export var step_distance: float = 1.0
var _distance_accumulated: float = 0.0
var _steps_taken: int = 0
```

- [x] In `_physics_process`, after the position update, accumulate distance and emit on threshold:

```gdscript
var move_amount := (move * speed * delta).length()
_distance_accumulated += move_amount
if _distance_accumulated >= step_distance:
    _distance_accumulated -= step_distance
    _steps_taken += 1
    ExplorationEvents.step_taken.emit(get_parent())
    Log.debug("step_taken", "count", _steps_taken)
```

The `_distance_accumulated -= step_distance` (not `= 0.0`) is intentional: it preserves any overshoot, keeping step rate accurate at any framerate.

`_steps_taken` is a debug counter — useful for verifying the signal fires. Can be removed later.

`Log.debug("step_taken", "count", _steps_taken)` uses the Logger under the level that gets filtered in production, so it's safe to leave in.

- [x] Run the game. Move the character and confirm `step_taken count N` appears in the Output panel.

---

## Task 4 — StepCounter ✅ (with caveats)

**What this is:** A simple node that listens to `ExplorationEvents.step_taken` and counts down. When the counter hits zero it emits `threshold_reached` and resets. The counter starts at 256 and decrements by a random amount (1–8) per step — this is the classic random encounter feel.

**Where it lives:** In the overworld scene, **not** inside the overworld_character scene. It's a system-level concern, not per-character. Connected to MovementComponent purely through the event bus — no parent-child relationship needed. In the test scene, it sits under a "System" node alongside other overworld systems.

**⚠️ Caveat — player-only filtering not yet active:** The signal carries `who: Node3D`, and StepCounter's callback receives it as `_who`. Eventually, StepCounter should filter with `if not who.is_player: return` so NPCs walking around don't trigger encounter countdowns. For now, since there are no NPCs in the scene, it's accepted as-is. When NPC overworld characters appear, this filter must be added.

**Files:**
- Created: `scripts/characters/overworld/StepCounter.gd` (not `scripts/overworld/` — placed alongside other overworld character scripts)
- No `.tscn` yet — placed as a raw node in the editor scene tree (no need for a separate scene file until reuse is needed)

- [x] Created `scripts/characters/overworld/StepCounter.gd`:

```gdscript
class_name StepCounter
extends Node

signal threshold_reached

const RESET_VALUE: int = 256

var _counter: int = RESET_VALUE

func _ready() -> void:
	Log.info("StepCounter ready, counter =", _counter)
	ExplorationEvents.step_taken.connect(_on_step_taken)

func _exit_tree() -> void:
	ExplorationEvents.step_taken.disconnect(_on_step_taken)

func _on_step_taken(_who: Node3D) -> void:
	_counter -= randi_range(1, 8)
	Log.debug("step_counter", "remaining", _counter)
	if _counter <= 0:
		_counter = RESET_VALUE
		Log.info("StepCounter threshold reached, resetting to", RESET_VALUE)
		threshold_reached.emit()
```

Notes on the implementation:
- `_who` is prefixed with underscore because it's unused — will become `who` once player filtering is added.
- `Log.debug("step_counter", "remaining", _counter)` shows the countdown per step — helpful for tuning, safe to leave in (debug level is filtered in production).
- Disconnects from the bus in `_exit_tree()` — required by project convention (CLAUDE.md: "Always disconnect in `_exit_tree()`").

- [x] Run the game and walk around. `StepCounter ready, counter = 256` should appear at startup, and `step_counter remaining N` should tick down each step. `StepCounter threshold reached` appears roughly every 256 steps.

---

## Task 5 — EncounterPool ✅

**What this is:** Holds an array of `EncounterPoolEntry` resources and picks one composition using weighted random selection when asked. Each area's `EncounterManager` has its own `EncounterPool` with its own authored entries.

**Weighted random:** Each `EncounterPoolEntry` has a `weight` value. The pool rolls a random number against the sum of all weights and walks down the list until it finds the winner. Higher weight = more likely. Adding a rare encounter just means giving its entry a low weight — no percentages to rebalance.

**Why entries, not raw `CombatConfig`s:** Weight is a property of "how common this encounter is *in this pool*", not of the encounter itself. The same `CombatConfig` could appear in two pools at different weights. Pairing composition and weight via a tiny entry resource keeps authoring clean in the inspector (one foldout per entry with both fields side-by-side) and avoids parallel-array desync bugs.

**⚠️ Caveat — folder:** Lives in `scripts/exploration/` and `scenes/exploration/`, not `scripts/overworld/` as originally planned. `exploration/` is now the canonical home for all overworld/encounter scripts.

**Files:**
- Create: `scripts/exploration/EncounterPool.gd`
- Create: `scenes/exploration/EncounterPool.tscn`

- [x] Create `scripts/exploration/EncounterPool.gd`:

```gdscript
class_name EncounterPool
extends Node

@export var entries: Array[EncounterPoolEntry] = []

func pick() -> CombatConfig:
    if entries.is_empty():
        Log.warn("EncounterPool.pick() called but entries array is empty")
        return null

    var total_weight: int = 0
    for entry in entries:
        total_weight += entry.weight

    var roll: int = randi() % total_weight
    for entry in entries:
        roll -= entry.weight
        if roll < 0:
            Log.info("EncounterPool picked:", entry.composition.resource_path)
            return entry.composition

    # Fallback — rounding safety net
    return entries[-1].composition
```

- [x] Create `scenes/exploration/EncounterPool.tscn`: new scene, `Node` root named `EncounterPool`, attach script, save.

- [x] Commit.

---

## Task 6 — CombatEnvironment + CombatBGM + EncounterManager

**What this is:** The per-map encounter trigger system, built as composition. `EncounterManager` is the thin glue node; its four children are focused components:
- `StepCounter` — emits `threshold_reached` (built in Task 4)
- `EncounterPool` — picks a weighted random `CombatConfig` (built in Task 5)
- `CombatEnvironment` — **data holder**: `PackedScene` of the 3D combat backdrop for this area
- `CombatBGM` — **data holder**: `AudioStream` of the combat track for this area

When `StepCounter` fires, the manager asks the pool for a composition, then reads the environment and BGM off its own sibling children, and emits all three on `CombatEvents.encounter_triggered`. That's the whole script.

**Why `CombatEnvironment` and `CombatBGM` are nodes, not exports on `EncounterManager`:** They start as trivial data holders, but both will almost certainly grow behavior — env fade-in, BGM crossfade on boss phase. Building them as components from the start means when that behavior arrives, it goes inside the existing node with no plumbing changes. Also aligns with "if you can name the concern, it deserves its own node."

**Files:**
- Create: `scripts/overworld/CombatEnvironment.gd`
- Create: `scripts/overworld/CombatBGM.gd`
- Create: `scripts/overworld/EncounterManager.gd`
- Create: `scenes/overworld/CombatEnvironment.tscn`
- Create: `scenes/overworld/CombatBGM.tscn`
- Create: `scenes/overworld/EncounterManager.tscn`

- [x] Create `scripts/overworld/CombatEnvironment.gd`:

```gdscript
class_name CombatEnvironment
extends Node

# Authored per-map. Points at the 3D scene that should be instanced as the
# combat backdrop for this area. Stays a data holder for now; room to grow
# (fade-in on mount, day/night variants, etc.) as the node it already is.
@export var scene: PackedScene
```

- [x] Create `scripts/overworld/CombatBGM.gd`:

```gdscript
class_name CombatBGM
extends Node

# Authored per-map. The BGM track played during combat in this area.
# Stays a data holder for now; room to grow into crossfade / boss-phase logic.
@export var stream: AudioStream
```

- [x] Create `scripts/overworld/EncounterManager.gd`:

```gdscript
class_name EncounterManager
extends Node

@onready var step_counter: StepCounter = $StepCounter
@onready var encounter_pool: EncounterPool = $EncounterPool
@onready var combat_environment: CombatEnvironment = $CombatEnvironment
@onready var combat_bgm: CombatBGM = $CombatBGM

func _ready() -> void:
    Log.info("EncounterManager ready")
    step_counter.threshold_reached.connect(_on_threshold_reached)

func _on_threshold_reached() -> void:
    var composition := encounter_pool.pick()
    if composition == null:
        return
    CombatEvents.encounter_triggered.emit(
        composition,
        combat_environment.scene,
        combat_bgm.stream,
    )
```

- [x] Create `scenes/overworld/CombatEnvironment.tscn`: new scene, `Node` root named `CombatEnvironment`, attach script, save.

- [x] Create `scenes/overworld/CombatBGM.tscn`: new scene, `Node` root named `CombatBGM`, attach script, save.

- [x] Create `scenes/overworld/EncounterManager.tscn`:
  - Root: `Node` named `EncounterManager`, attach `EncounterManager.gd`
  - Add child: instance `StepCounter.tscn`, name it `StepCounter`
  - Add child: instance `EncounterPool.tscn`, name it `EncounterPool`
  - Add child: instance `CombatEnvironment.tscn`, name it `CombatEnvironment`
  - Add child: instance `CombatBGM.tscn`, name it `CombatBGM`
  - Save

- [ ] Commit:
```bash
git add scripts/overworld/CombatEnvironment.gd scripts/overworld/CombatBGM.gd scripts/overworld/EncounterManager.gd
git add scenes/overworld/CombatEnvironment.tscn scenes/overworld/CombatBGM.tscn scenes/overworld/EncounterManager.tscn
git commit -m "Add EncounterManager + CombatEnvironment + CombatBGM: per-map encounter trigger composition"
```

---

## Task 7 — VitalsComponent

**What this is:** The component that tracks current HP, MP, and AP for a combat character. It reads its initial values from `CharacterSaveData` (players) or `CombatData.MaxHP/MaxMP` (enemies) at the start of each encounter, and resets between encounters.

**Files:**
- Create: `scripts/combat/VitalsComponent.gd`
- Create: `scenes/combat/components/VitalsComponent.tscn`

- [x] Create `scripts/combat/VitalsComponent.gd`:

```gdscript
class_name VitalsComponent
extends Node

var cur_hp: int = 0
var cur_mp: int = 0
var cur_ap: int = 0

var _max_hp: int = 0
var _max_mp: int = 0

func setup(hp: int, mp: int) -> void:
    _max_hp = hp
    _max_mp = mp
    cur_hp = hp
    cur_mp = mp
    cur_ap = 3    # GDD: all actors start combat with 3 AP
    Log.info("VitalsComponent setup — HP:", cur_hp, "MP:", cur_mp)

func reset() -> void:
    cur_ap = 3
    Log.info("VitalsComponent reset — AP reset to 3")
```

`setup()` is called at `CombatStart` (reading from save data or enemy base stats). `reset()` will be called by the state reset pass — for now just resets AP.

- [x] Create `scenes/combat/components/VitalsComponent.tscn`: `Node` root named `VitalsComponent`, attach script, save. You'll need to create the `scenes/combat/components/` folder first.

- [x] Commit:
```bash
git add scripts/combat/VitalsComponent.gd scenes/combat/components/VitalsComponent.tscn
git commit -m "Add VitalsComponent: cur_hp/mp/ap with setup() and reset()"
```

---

## Task 8 — Component stubs: ActiveTokens + CombatSFXComponent

**What these are:** Two components that need to exist in the scene tree now so `CombatCharacter.tscn` can be fully assembled. Stubs only — behaviour comes later.

`CombatInputComponent` was originally planned here. It has been **deleted** — combat input is a scene-level concern, not a per-character component. See `docs/superpowers/specs/2026-04-13-combat-visuals-design.md`.

**Files:**
- Create: `scripts/combat/ActiveTokens.gd` + `scenes/combat/components/ActiveTokens.tscn`
- Create: `scripts/combat/CombatSFXComponent.gd` + `scenes/combat/components/CombatSFXComponent.tscn`

- [ ] Create `scripts/combat/ActiveTokens.gd`:

```gdscript
class_name ActiveTokens
extends Node

# Holds active combat tokens for this character.
# Emits signals when tokens are added, removed, or updated.
# Stub — full implementation in a future task.

signal token_added(token: Resource)
signal token_removed(token: Resource)
signal token_updated(token: Resource)

func flush() -> void:
    Log.info("ActiveTokens flushed (stub)")
```

- [ ] Create `scripts/combat/CombatSFXComponent.gd`:

```gdscript
class_name CombatSFXComponent
extends Node

# Plays character-level audio: swing, cast, hurt, KO, footstep.
# Stub — full implementation in a future task.

func play_swing() -> void: pass
func play_cast() -> void: pass
func play_hurt() -> void: pass
func play_ko() -> void: pass
func play_footstep() -> void: pass
```

- [ ] Create both `.tscn` files following the same pattern as Task 7.

- [ ] Commit:
```bash
git add scripts/combat/ActiveTokens.gd scenes/combat/components/ActiveTokens.tscn
git add scripts/combat/CombatSFXComponent.gd scenes/combat/components/CombatSFXComponent.tscn
git commit -m "Add ActiveTokens and CombatSFXComponent stubs"
```

---

## Task 9 — CombatVisuals scene skeleton

**What changed:** The original plan here was to patch the overworld `VisualComponent` for combat use. That approach has been **replaced**. Combat gets its own dedicated visual component — `CombatVisuals` — which owns the `AnimatedSprite3D`, tweens local position for approach/recover, and drives the animation beat API. The overworld `VisualComponent` is not touched.

**Full spec:** `docs/superpowers/specs/2026-04-13-combat-visuals-design.md` — read the `CombatVisuals` API section before writing any code here.

**Files:**
- Create: `scripts/combat/CombatVisuals.gd`
- Create: `scenes/combat/components/CombatVisuals.tscn`

- [ ] Create `scripts/combat/CombatVisuals.gd` — skeleton only, all methods stubbed:

```gdscript
class_name CombatVisuals
extends Node3D

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

var _base_state: StringName = &"Idle"
var _action_playing: bool = false

func setup(sprite_frames: SpriteFrames) -> void:
    sprite.sprite_frames = sprite_frames
    sprite.play(_base_state)
    Log.info("CombatVisuals setup")

func set_base_state(state: StringName) -> void:
    _base_state = state
    if not _action_playing:
        sprite.play(_base_state)
    Log.debug("CombatVisuals base state set:", state)

func approach(target_offset: Vector3, duration: float = 0.2) -> void:
    Log.debug("CombatVisuals approach (stub)")

func recover(duration: float = 0.2) -> void:
    Log.debug("CombatVisuals recover (stub)")

func attack_to_motion_hold() -> void: pass
func attack_to_strike_hold() -> void: pass
func attack_to_recover_hold() -> void: pass
func attack_finish() -> void: pass

func cast_to_motion_hold() -> void: pass
func cast_to_release_hold() -> void: pass
func cast_to_recover_hold() -> void: pass
func cast_finish() -> void: pass

func play_combat_entry() -> void: pass
func play_combat_exit() -> void: pass
func play_item_use() -> void: pass
func play_hurt() -> void: pass
func play_dodge_slide() -> void: pass
func play_ko() -> void: pass
func play_custom(anim_name: String) -> void: pass
```

- [ ] Create `scenes/combat/components/CombatVisuals.tscn` in the Godot editor:
  - Root: `Node3D` named `CombatVisuals`, attach `CombatVisuals.gd`
  - Add child: `AnimatedSprite3D` named `AnimatedSprite3D`
  - Save

- [ ] Run the game. No errors. The scene should open cleanly in the editor.

- [ ] Commit:
```bash
git add scripts/combat/CombatVisuals.gd scenes/combat/components/CombatVisuals.tscn
git commit -m "Add CombatVisuals skeleton: stubbed animation beat API"
```

---

## Task 10 — CombatCharacter scene

**What this is:** The composed scene for a single combatant in combat — player or enemy. Assembles the components from Tasks 7–9. The root script is thin: `initialize_player()` and `initialize_enemy()` fan data out to each component.

**Scene shape** (per `docs/superpowers/specs/2026-04-13-combat-visuals-design.md`):
```
CombatCharacter (Node3D)
  ├── VitalsComponent
  ├── ActiveTokens
  ├── CombatVisuals (Node3D)
  │     └── AnimatedSprite3D
  ├── CombatSFXComponent
  ├── VFXAnchor (Node3D)
  └── CombatTextAnchor (Node3D)
```

**Files:**
- Create: `scripts/combat/CombatCharacter.gd`
- Create: `scenes/combat/CombatCharacter.tscn`

- [ ] Create `scripts/combat/CombatCharacter.gd`:

```gdscript
class_name CombatCharacter
extends Node3D

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visuals: CombatVisuals = $CombatVisuals
@onready var sfx: CombatSFXComponent = $CombatSFXComponent
@onready var vfx_anchor: Node3D = $VFXAnchor
@onready var combat_text_anchor: Node3D = $CombatTextAnchor

func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
    visuals.setup(data.character_sprite)
    vitals.setup(save_data.cur_hp, save_data.cur_mp, save_data.cur_ap)
    Log.info("CombatCharacter (player) initialized:", data.character_name)

func initialize_enemy(data: EnemyData) -> void:
    visuals.setup(data.character_sprite)
    vitals.setup(data.max_hp, data.max_mp, data.starting_ap)
    Log.info("CombatCharacter (enemy) initialized:", data.character_name)

func reset_for_combat() -> void:
    vitals.reset()
    tokens.flush()

func get_anchor(kind: StringName) -> Node3D:
    match kind:
        &"vfx":         return vfx_anchor
        &"combat_text": return combat_text_anchor
    Log.error("CombatCharacter.get_anchor: unknown kind", kind, name)
    return null
```

- [ ] Create `scenes/combat/CombatCharacter.tscn` in the Godot editor:
  - Root: `Node3D` named `CombatCharacter`, attach `CombatCharacter.gd`
  - Add child: instance `scenes/combat/components/VitalsComponent.tscn`
  - Add child: instance `scenes/combat/components/ActiveTokens.tscn`
  - Add child: instance `scenes/combat/components/CombatVisuals.tscn`
  - Add child: instance `scenes/combat/components/CombatSFXComponent.tscn`
  - Add child: `Node3D` named `VFXAnchor` — set position to `(0, 1.0, 0)`
  - Add child: `Node3D` named `CombatTextAnchor` — set position to `(0, 1.8, 0)`
  - Save

- [ ] Run the game. No errors.

- [ ] Commit:
```bash
git add scripts/combat/CombatCharacter.gd scenes/combat/CombatCharacter.tscn
git commit -m "Add CombatCharacter scene: VitalsComponent, ActiveTokens, CombatVisuals, CombatSFXComponent, anchors"
```

---

## Task 11 — PlayerSpawner + EnemySpawner

**What these are:** Two sibling nodes inside `CombatScene`. `PlayerSpawner` owns the three player slots and permanently holds three `CombatCharacter` instances — one per party slot. `EnemySpawner` owns six enemy slots and instantiates/frees enemies per encounter.

**Files:**
- Create: `scripts/combat/PlayerSpawner.gd` + `scenes/combat/PlayerSpawner.tscn`
- Create: `scripts/combat/EnemySpawner.gd` + `scenes/combat/EnemySpawner.tscn`

- [ ] Create `scripts/combat/PlayerSpawner.gd`:

```gdscript
class_name PlayerSpawner
extends Node

# The three permanent combat_character nodes, one per party slot.
# Assigned via @onready — they are direct children of the slot nodes.
var _characters: Array[CombatCharacter] = []

func _ready() -> void:
    for slot in get_children():
        var character: CombatCharacter = slot.get_child(0)
        _characters.append(character)
    Log.info("PlayerSpawner ready, slots:", _characters.size())

func initialize() -> void:
    for i in _characters.size():
        var slot_data = PartyManager.get_slot(i)
        if slot_data.is_empty():
            continue
        _characters[i].initialize_player(slot_data["player_data"], slot_data["save_data"])
```

- [ ] Create `scripts/combat/EnemySpawner.gd`:

```gdscript
class_name EnemySpawner
extends Node

const CombatCharacterScene = preload("res://scenes/combat/CombatCharacter.tscn")

func initialize(composition: CombatConfig) -> void:
    clear()
    var slots := get_children()
    var enemy_data: Array[EnemyData] = [
        composition.enemy_slot1,
        composition.enemy_slot2,
        composition.enemy_slot3,
        composition.enemy_slot4,
        composition.enemy_slot5,
        composition.enemy_slot6,
    ]
    for i in enemy_data.size():
        if i >= slots.size():
            break
        if enemy_data[i] == null:
            continue
        var character: CombatCharacter = CombatCharacterScene.instantiate()
        slots[i].add_child(character)
        character.initialize_enemy(enemy_data[i])

func clear() -> void:
    for slot in get_children():
        for child in slot.get_children():
            child.queue_free()
    Log.info("EnemySpawner cleared")
```

- [ ] Create `scenes/combat/PlayerSpawner.tscn`:
  - Root: `Node` named `PlayerSpawner`, attach script
  - Three children: `Node3D` named `Slot1`, `Slot2`, `Slot3` — position them in 3D space at authored positions (roughly -2, 0, 2 on the X axis for now)
  - Inside each Slot: instance a `CombatCharacter.tscn`
  - Save

- [ ] Create `scenes/combat/EnemySpawner.tscn`:
  - Root: `Node` named `EnemySpawner`, attach script
  - Six children: `Node3D` named `Slot1`–`Slot6` — position them opposite the player slots
  - Leave slots empty — enemies are instantiated at runtime
  - Save

- [ ] Commit:
```bash
git add scripts/combat/PlayerSpawner.gd scenes/combat/PlayerSpawner.tscn
git add scripts/combat/EnemySpawner.gd scenes/combat/EnemySpawner.tscn
git commit -m "Add PlayerSpawner and EnemySpawner: actor slot management"
```

---

## Task 12 — CombatScene coordinator

**What this is:** The root of the combat scene. It receives the three pieces of encounter data — composition, environment scene, BGM stream — and fans them out. It directly owns two built-in children for the env mount and BGM playback (`EnvironmentMount: Node3D` and `BGMPlayer: AudioStreamPlayer`) because those are a few lines of plumbing each, not behavior worth its own custom node.

**Why no dedicated `CombatBackground` node:** The old plan had one focused node that owned env + BGM. With the env now a full 3D `PackedScene` (instanced under a mount) and BGM being a single stream, there's no shared behavior between them. They're simpler as two direct children of `CombatScene` than as members of a shared node.

**Files:**
- Create: `scripts/combat/CombatScene.gd`
- Create: `scenes/combat/CombatScene.tscn`

- [ ] Create `scripts/combat/CombatScene.gd`:

```gdscript
class_name CombatScene
extends Node

@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner

func initialize(composition: CombatConfig, environment_scene: PackedScene, bgm_stream: AudioStream) -> void:
    Log.info("CombatScene initializing...")
    _reset_state()
    _mount_environment(environment_scene)
    _play_bgm(bgm_stream)
    player_spawner.initialize()
    enemy_spawner.initialize(composition)
    Log.info("CombatScene initialized")

func _reset_state() -> void:
    # Explicit state reset before every encounter.
    # See spec: "State Reset at CombatStart"
    player_spawner.reset_characters()
    enemy_spawner.clear()
    _clear_environment()
    bgm_player.stop()

func _mount_environment(scene: PackedScene) -> void:
    if scene == null:
        Log.warn("CombatScene: no environment scene provided")
        return
    var instance: Node3D = scene.instantiate()
    environment_mount.add_child(instance)

func _clear_environment() -> void:
    for child in environment_mount.get_children():
        child.queue_free()

func _play_bgm(stream: AudioStream) -> void:
    if stream == null:
        Log.warn("CombatScene: no BGM stream provided")
        return
    bgm_player.stream = stream
    bgm_player.play()
```

- [ ] Add `reset_characters()` to `PlayerSpawner.gd`:

```gdscript
func reset_characters() -> void:
    for character in _characters:
        character.reset_for_combat()
```

- [ ] Create `scenes/combat/CombatScene.tscn`:
  - Root: `Node` named `CombatScene`, attach `CombatScene.gd`
  - Child: `Node3D` named `EnvironmentMount` — the 3D env scene gets instanced here at runtime
  - Child: `AudioStreamPlayer` named `BGMPlayer`
  - Child: instance `PlayerSpawner.tscn`
  - Child: instance `EnemySpawner.tscn`
  - Save

- [ ] Commit:
```bash
git add scripts/combat/CombatScene.gd scenes/combat/CombatScene.tscn
git add scripts/combat/PlayerSpawner.gd
git commit -m "Add CombatScene coordinator: mounts env, starts BGM, fans composition to spawners"
```

---

## Task 13 — PartyManager autoload

**What this is:** The autoload that holds `GlobalSaveData` and exposes party members. `start_new_game()` seeds the initial save with Skugge in slot 0. `recruit()` adds any character to the roster using their authored `PlayerData` as the source of truth for starting stats. For now the registry is hardcoded — proper folder scanning comes when more `.tres` files exist.

**Files:**
- Create: `scripts/autoloads/PartyManager.gd`
- Create: `scenes/autoloads/PartyManager.tscn`
- Modify: `scripts/characters/PlayerData.gd` — add `starting_level`

- [ ] Add `starting_level` to `PlayerData.gd`:

```gdscript
class_name PlayerData
extends CombatData

@export var character_portrait: Texture2D
@export var growth_table: GrowthTable
@export var allowed_gear: Array[EquipmentType.Flags] = []
@export var starting_level: int = 1
```

When you author Marta's `PlayerData.tres` later, set her `starting_level = 3` and her `MaxHP`/`MaxMP` to match a level 3 character. `recruit()` reads whatever is authored there — no special casing needed.

- [ ] Create `scripts/autoloads/PartyManager.gd`:

```gdscript
class_name PartyManager
extends Node

var save_data: GlobalSaveData = null

# Registry of all known PlayerData resources, keyed by character_ID.
# TODO: replace with folder scan once more PlayerData .tres files exist.
var _registry: Dictionary = {}

func _ready() -> void:
    Log.info("PartyManager ready")
    _load_registry()
    _load_save()

func _load_registry() -> void:
    # Hardcoded for now — add an entry here each time you create a PlayerData .tres.
    # Example once Skugge's .tres exists:
    # _registry["skugge"] = preload("res://data/characters/skugge.tres")
    pass

func _load_save() -> void:
    # TODO: load from disk. For now, always start a new game.
    start_new_game()

func start_new_game() -> void:
    save_data = GlobalSaveData.new()
    # Skugge is always the starting character.
    # Add her PlayerData .tres to _registry first, then uncomment:
    # recruit("skugge")
    # save_data.party_slots[0] = "skugge"
    Log.info("PartyManager: new game started")

# Adds a character to the roster using their PlayerData as the starting template.
# Safe to call multiple times — will not overwrite existing save data.
func recruit(char_id: String) -> void:
    if save_data.roster.has(char_id):
        Log.warn("recruit() called for already-known character:", char_id)
        return
    var player_data: PlayerData = _registry.get(char_id, null)
    if player_data == null:
        Log.error("recruit() failed — no PlayerData registered for:", char_id)
        return
    var char_save := CharacterSaveData.new()
    char_save.character_level = player_data.starting_level
    char_save.cur_hp = player_data.MaxHP
    char_save.cur_mp = player_data.MaxMP
    save_data.roster[char_id] = char_save
    Log.info("Recruited:", char_id, "at level", char_save.character_level)

# Assigns a roster character to an active party slot (0, 1, or 2).
func assign_slot(slot: int, char_id: String) -> void:
    if not save_data.roster.has(char_id):
        Log.error("assign_slot() failed —", char_id, "not in roster")
        return
    save_data.party_slots[slot] = char_id
    Log.info("Party slot", slot, "assigned to:", char_id)

# Returns {player_data: PlayerData, save_data: CharacterSaveData} for the given slot,
# or an empty Dictionary if the slot is empty or unregistered.
func get_slot(index: int) -> Dictionary:
    if index >= save_data.party_slots.size():
        return {}
    var char_id: String = save_data.party_slots[index]
    if char_id.is_empty():
        return {}
    var player_data: PlayerData = _registry.get(char_id, null)
    var char_save: CharacterSaveData = save_data.roster.get(char_id, null)
    if player_data == null or char_save == null:
        return {}
    return { "player_data": player_data, "save_data": char_save }
```

- [ ] Create `scenes/autoloads/PartyManager.tscn`: `Node` root named `PartyManager`, attach script, save.

- [ ] Register in `Project → Project Settings → Autoload`: path `res://scenes/autoloads/PartyManager.tscn`, name `PartyManager`.

**To test mid-game recruitment in Task 16:** add a simple `Area3D` to `Map_Test.tscn` with a script that calls `PartyManager.recruit("marta")` and `PartyManager.assign_slot(1, "marta")` on `body_entered`. Once Marta's `PlayerData.tres` exists and is registered, she'll appear in combat slot 1 after the player walks through the trigger.

- [ ] Commit:
```bash
git add scripts/autoloads/PartyManager.gd scenes/autoloads/PartyManager.tscn
git add scripts/characters/PlayerData.gd
git commit -m "Add PartyManager: recruit(), assign_slot(), start_new_game() with starting_level on PlayerData"
```

---

## Task 14 — ScreenFader

**What this is:** A fullscreen `ColorRect` that fades to black and back. `GameManager` awaits `fade_out()` and `fade_in()` — those methods return when the animation is complete.

**In GDScript, `await signal_name`** pauses execution of the current function until the signal fires. This is how you write "do A, then wait, then do B" without callbacks.

**Files:**
- Create: `scripts/core/ScreenFader.gd`
- Create: `scenes/core/ScreenFader.tscn`

- [ ] Create `scripts/core/ScreenFader.gd`:

```gdscript
class_name ScreenFader
extends CanvasLayer

signal fade_out_done
signal fade_in_done

@onready var rect: ColorRect = $ColorRect
@onready var anim: AnimationPlayer = $AnimationPlayer

func fade_out() -> void:
    anim.play("fade_out")
    await fade_out_done

func fade_in() -> void:
    anim.play("fade_in")
    await fade_in_done
```

- [ ] Create `scenes/core/ScreenFader.tscn`:
  - Root: `CanvasLayer` named `ScreenFader`, attach script
  - Child: `ColorRect` named `ColorRect` — set to full screen, black, initial `modulate.a = 0`
  - Child: `AnimationPlayer` named `AnimationPlayer`
  - In AnimationPlayer, create two animations:
    - `fade_out`: animate `ColorRect.modulate:a` from `0.0` to `1.0` over 0.3s. Add a **Call Method Track** targeting the `ScreenFader` node — at the final keyframe (0.3s), call `emit_signal("fade_out_done")`
    - `fade_in`: animate `ColorRect.modulate:a` from `1.0` to `0.0` over 0.3s. Same thing — Call Method Track at the end calling `emit_signal("fade_in_done")`
    - **How to add a Call Method Track:** in AnimationPlayer, click "Add Track" → "Call Method Track" → select the `ScreenFader` node → click the timeline at 0.3s → pick `emit_signal` → set the argument to the signal name string
  - Save

- [ ] Commit:
```bash
git add scripts/core/ScreenFader.gd scenes/core/ScreenFader.tscn
git commit -m "Add ScreenFader: awaitable fade_out/fade_in via AnimationPlayer"
```

---

## Task 15 — GameManager FSM ⚠️ REPLACED

> **This task has been replaced.** See `docs/superpowers/plans/2026-04-13-game-flow-bootstrap.md` — Task C defines the three-state GameManager (MENU / OVERWORLD / COMBAT) with scene mounting/unmounting, Main Menu, and `Globals.skip_to_overworld` dev toggle. Use that version instead of the two-state version below.

<details>
<summary>Original two-state version (superseded — kept for reference)</summary>

```gdscript
class_name GameManager
extends Node

enum State { OVERWORLD, COMBAT }

var state: State = State.OVERWORLD
var current_overworld: Node = null

@onready var fader: ScreenFader = $ScreenFader
@onready var combat_scene: CombatScene = $CombatScene

func _ready() -> void:
    Log.info("GameManager ready")
    CombatEvents.encounter_triggered.connect(_on_encounter_triggered)
    combat_scene.process_mode = Node.PROCESS_MODE_DISABLED

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("debug_trigger_combat"):
        CombatEvents.encounter_triggered.emit(CombatConfig.new(), null, null)

func _on_encounter_triggered(composition: CombatConfig, environment_scene: PackedScene, bgm_stream: AudioStream) -> void:
    if state != State.OVERWORLD:
        return
    state = State.COMBAT
    if current_overworld != null:
        current_overworld.process_mode = Node.PROCESS_MODE_DISABLED
    await fader.fade_out()
    combat_scene.process_mode = Node.PROCESS_MODE_INHERIT
    combat_scene.initialize(composition, environment_scene, bgm_stream)
    await fader.fade_in()
    Log.info("GameManager: entered COMBAT state")

func end_combat() -> void:
    await fader.fade_out()
    combat_scene.process_mode = Node.PROCESS_MODE_DISABLED
    if current_overworld != null:
        current_overworld.process_mode = Node.PROCESS_MODE_INHERIT
    await fader.fade_in()
    state = State.OVERWORLD
    Log.info("GameManager: returned to OVERWORLD state")
```

</details>

---

## Task 16 — Register GameManager + test map ⚠️ REPLACED

> **This task has been replaced.** See `docs/superpowers/plans/2026-04-13-game-flow-bootstrap.md` — Task D covers autoload registration and main scene setup with the new flow. The key difference: `game_manager.tscn` is now the main scene (not `Map_Test.tscn`), and autoload order includes Globals first.

---

## Task 17 — End-to-end verification

**What to verify (updated for the new flow):**

- [ ] **Dev mode** (`Globals.skip_to_overworld = true`): Run the game (F5). Game launches straight to overworld. Check Output panel:
  - All autoloads log `ready` — Globals, ExplorationEvents, CombatEvents, PartyManager, GameManager
  - `StepCounter ready, counter = 256` appears
  - `EncounterManager ready` appears

- [ ] **Menu mode** (`Globals.skip_to_overworld = false`): Run the game. MainMenu appears. Press New Game. Fades to overworld. Same checks as above.

- [ ] Walk the player character. After roughly 256 steps:
  - `StepCounter threshold reached, resetting to 256`
  - `EncounterPool picked: ...`
  - `CombatScene initializing...`
  - Fade to black, combat scene appears (blank for now — env and BGM are null in the test pool entry)
  - `CombatScene: no environment scene provided` and `CombatScene: no BGM stream provided` warnings — expected
  - `CombatScene initialized` in log

- [ ] Press F1 (debug hotkey):
  - Same flow triggers immediately without walking

- [ ] When everything is visible and logging correctly, final commit:
```bash
git add .
git commit -m "End-to-end combat transition pipe: menu → overworld → fade → combat"
```

- [ ] Add the `debug_trigger_combat` input action in `Project → Project Settings → Input Map`. Add it as a new action, bind it to `F1`.

- [ ] Open `scenes/core/game_manager.tscn` in the Godot editor:
  - Attach `GameManager.gd` to the root `GameManager` node
  - Instance `scenes/core/ScreenFader.tscn` as a child
  - Instance `scenes/combat/CombatScene.tscn` as a child
  - Save

- [ ] Commit:
```bash
git add scripts/core/GameManager.gd scenes/core/game_manager.tscn
git commit -m "Add GameManager FSM: OVERWORLD/COMBAT states, fade transition, debug hotkey"
```

---

## Task 16 — Register GameManager as autoload + wire a test map

**What this does:** Registers `GameManager` as the final autoload, then builds a minimal test map with an `EncounterManager` so the full pipe can be exercised.

- [ ] Register `GameManager` in `Project → Project Settings → Autoload`:
  - Path: `res://scenes/core/game_manager.tscn`, name: `GameManager`
  - **Order matters:** GameManager should load after CombatEvents and ExplorationEvents so those buses exist when it connects to them. Drag to reorder if needed:
    1. ExplorationEvents
    2. CombatEvents
    3. PartyManager
    4. GameManager

- [ ] Create a minimal test map scene `scenes/overworld/Map_Test.tscn`:
  - Root: `Node3D` named `Map_Test`
  - Add a script `scripts/overworld/map_test.gd` with just the self-registration:

```gdscript
extends Node3D

func _enter_tree() -> void:
    GameManager.current_overworld = self

func _exit_tree() -> void:
    GameManager.current_overworld = null
```

  - Instance `scenes/overworld/EncounterManager.tscn` as a child
  - Author one `CombatConfig` `.tres` file: `File → New Resource → CombatConfig`, leave all six enemy slots null for now, save as `data/combat/test_encounter.tres` (create the folder).
  - Author one `EncounterPoolEntry` `.tres` file: `File → New Resource → EncounterPoolEntry`, set `composition` to the `CombatConfig` above, `weight = 10`, save as `data/combat/test_pool_entry.tres`.
  - On the `EncounterPool` child of `EncounterManager`, add the entry to the `entries` array.
  - On the `CombatEnvironment` child of `EncounterManager`, leave `scene` null for now (CombatScene tolerates it and logs a warning — we're just testing the pipe).
  - On the `CombatBGM` child of `EncounterManager`, leave `stream` null for now (same reason).
  - Add your existing overworld player character to the scene so `MovementComponent` can emit steps

- [ ] Set `Map_Test.tscn` as the main scene (`Project → Project Settings → Application → Run → Main Scene`).

- [ ] Commit:
```bash
git add scenes/overworld/Map_Test.tscn scripts/overworld/map_test.gd
git commit -m "Add Map_Test scene for end-to-end encounter trigger testing"
```

---

## Task 17 — End-to-end verification

**What to verify:**

- [ ] Run the game (F5). Check Output panel:
  - All autoloads log `ready` — GameManager, PartyManager, CombatEvents, ExplorationEvents
  - `StepCounter ready, counter = 256` appears
  - `EncounterManager ready` appears

- [ ] Walk the player character. After roughly 256 steps:
  - `StepCounter threshold reached, resetting to 256`
  - `EncounterPool picked: ...`
  - `CombatScene initializing...`
  - Fade to black, combat scene appears (blank for now — env and BGM are null in the test pool entry)
  - `CombatScene: no environment scene provided` and `CombatScene: no BGM stream provided` warnings — expected, we left both null
  - `CombatScene initialized` in log

- [ ] Press F1 (debug hotkey):
  - Same flow triggers immediately without walking, with the same null-env/null-BGM warnings

- [ ] Verify the enemy/player Log output:
  - If `PartyManager` has no party data yet, `PlayerSpawner` will skip slots silently (the `if slot_data.is_empty(): continue` guard). That's expected — party data wiring comes later.

- [ ] When everything is visible and logging correctly, final commit:
```bash
git add .
git commit -m "End-to-end combat transition pipe: overworld → fade → combat scene init"
```

---

## What Comes Next (out of scope for this plan)

- Populating `PartyManager` with real `PlayerData` `.tres` files and `CharacterSaveData`
- Authored `CombatConfig` `.tres` files with real enemy compositions, `EncounterPoolEntry` `.tres` files tying them into area pools, and `PackedScene` / `AudioStream` assets for each area's `CombatEnvironment` and `CombatBGM`
- A reusable `EnvironmentTemplate.tscn` as the inherited-scene base for every map — holds the standard `OverworldEnvironment` + `EncounterManager` skeleton; each map is `New Inherited Scene` from it and only overrides the pool contents, combat env, BGM, and the overworld geometry
- Scripted (non-random) boss encounters: triggered directly from story events with their own unique composition / environment / BGM, bypassing the pool
- Return to overworld: call `GameManager.end_combat()` after a trigger (e.g. debug key)
- `CharacterSaveData` writeback at `CombatEnd`
- `TurnOrderManager` + combat FSM (the actual fight)
