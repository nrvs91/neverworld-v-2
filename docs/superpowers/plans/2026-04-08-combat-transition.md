# Combat Scene Transition & Data Flow — Implementation Plan

> **Note:** This plan is written for you to implement yourself. Each task explains what to build, why it exists, and what it should look like — you write the code. When something is unclear or you get stuck, ask and we'll work through it together. That's the whole point.

> **No automated tests in this project.** Verification steps mean: open Godot, run the scene (F5), check the Output panel for `Log.*` messages and errors.

**Goal:** Wire the full overworld → combat transition pipe so that walking around (or pressing a debug key) triggers a fade to the combat scene, where combatants spawn at authored positions and print their names and HP/MP to the console.

**Architecture:** Four autoloads handle global concerns (GameManager FSM, PartyManager, two event buses). The combat scene is a permanent child of GameManager — always in the tree, disabled when not active, composed of focused sub-nodes. EncounterManager on each map is a thin coordinator between a StepCounter and an EncounterPool.

**Spec:** `docs/superpowers/specs/2026-04-08-combat-transition-design.md`

**Tech Stack:** Godot 4.6, GDScript only. No C#. Use `Log.*` not `print()`.

---

## File Map

Files to create or modify, grouped by concern:

```
# Data resources
scripts/characters/GlobalSaveData.gd        NEW — save file root: party slots + character saves
scripts/combat/CombatConfig.gd              NEW — one encounter definition: enemies, background, BGM

# Autoloads / event buses
scripts/autoloads/ExplorationEvents.gd      NEW — exploration domain signals (step_taken)
scripts/autoloads/CombatEvents.gd           NEW — combat domain signals (encounter_triggered)
scripts/autoloads/PartyManager.gd           NEW — holds GlobalSaveData, exposes party slots
scenes/autoloads/ExplorationEvents.tscn     NEW
scenes/autoloads/CombatEvents.tscn          NEW
scenes/autoloads/PartyManager.tscn          NEW

# Overworld / encounter trigger
scripts/characters/overworld/MovementComponent.gd   MODIFY — emit step_taken via ExplorationEvents
scripts/overworld/StepCounter.gd            NEW — counts steps, emits threshold_reached
scripts/overworld/EncounterPool.gd          NEW — weighted random pick from CombatConfigs
scripts/overworld/EncounterManager.gd       NEW — thin connector between StepCounter + EncounterPool
scenes/overworld/StepCounter.tscn           NEW
scenes/overworld/EncounterPool.tscn         NEW
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
scripts/combat/CombatBackground.gd          NEW — swaps background visual + BGM
scripts/combat/PlayerSpawner.gd             NEW — owns player slots, inits permanent combat_characters
scripts/combat/EnemySpawner.gd              NEW — owns enemy slots, spawns/frees per encounter
scripts/combat/CombatScene.gd               NEW — thin coordinator, calls sub-spawners
scenes/combat/CombatBackground.tscn         NEW
scenes/combat/PlayerSpawner.tscn            NEW
scenes/combat/EnemySpawner.tscn             NEW
scenes/combat/CombatScene.tscn              NEW

# Core / GameManager
scripts/core/ScreenFader.gd                 NEW — fade_out / fade_in, awaitable
scripts/core/GameManager.gd                 NEW — FSM: OVERWORLD / COMBAT states
scenes/core/ScreenFader.tscn                NEW
scenes/core/game_manager.tscn               MODIFY — add ScreenFader + CombatScene as children
```

---

## Task 1 — GlobalSaveData + CombatConfig resources

**What these are:** Two `Resource` subclasses that hold authored data. `GlobalSaveData` is the save file root — it knows which characters are in the party and what their current stats are. `CombatConfig` defines one encounter: which enemies appear, in which slots, with what background.

**Files:**
- Create: `scripts/characters/GlobalSaveData.gd`
- Create: `scripts/combat/CombatConfig.gd`

**In Godot, a Resource subclass** is a script that extends `Resource`. You can save instances as `.tres` files in the editor and attach them as exports. Think of `.tres` files as your game's data spreadsheets.

- [ ] Create `scripts/characters/GlobalSaveData.gd`:

```gdscript
class_name GlobalSaveData
extends Resource

# Which characters are currently in the party, by character_ID string.
# Index = party slot (0, 1, 2). Always 3 entries — empty slot = "".
@export var party_slots: Array[String] = ["", "", ""]

# All known characters, keyed by character_ID.
# Maps String → CharacterSaveData.
# Untyped because GDScript typed dicts require Godot 4.4+.
@export var roster: Dictionary = {}
```

- [ ] Create `scripts/combat/CombatConfig.gd`:

```gdscript
class_name CombatConfig
extends Resource

# Relative weight for weighted random pick within an EncounterPool.
# Higher = more common. Not a percentage — just relative to other entries.
@export var weight: int = 10

# Which enemies appear in which slots. Index 0–5 = EnemySlot1–6.
# Null entry = empty slot. Untyped Array to allow null entries.
@export var enemy_slots: Array = []

@export var background: Texture2D
@export var bgm: AudioStream
```

- [ ] Open Godot editor. Verify both scripts appear without errors in the Script editor (no red underlines).

- [ ] Commit:
```bash
git add scripts/characters/GlobalSaveData.gd scripts/combat/CombatConfig.gd
git commit -m "Add GlobalSaveData and CombatConfig resource classes"
```

---

## Task 2 — Event buses: ExplorationEvents + CombatEvents

**What these are:** Autoloads that hold only signal declarations — no logic, no state. Any node anywhere in the game can emit or connect to these. They keep systems decoupled: `MovementComponent` doesn't know about `StepCounter`; it just emits a signal into the void.

**In Godot, autoloads** are nodes that are always present in the scene tree, accessible by their registered name from any script. You register them in `Project → Project Settings → Autoload`.

- [ ] Create `scripts/autoloads/ExplorationEvents.gd`:

```gdscript
class_name ExplorationEvents
extends Node

signal step_taken
```

- [ ] Create `scripts/autoloads/CombatEvents.gd`:

```gdscript
class_name CombatEvents
extends Node

signal encounter_triggered(config: CombatConfig)
```

- [ ] For each script, create a matching `.tscn` scene file. In Godot editor:
  - Create a new scene → `Node` as root → rename root to `ExplorationEvents` → attach the script → save as `scenes/autoloads/ExplorationEvents.tscn`
  - Repeat for `CombatEvents`

- [ ] Register both in `Project → Project Settings → Autoload`:
  - Path: `res://scenes/autoloads/ExplorationEvents.tscn`, Node Name: `ExplorationEvents`
  - Path: `res://scenes/autoloads/CombatEvents.tscn`, Node Name: `CombatEvents`

- [ ] Run the game (F5). No errors should appear. The autoloads appear in the remote scene tree debugger under root.

- [ ] Commit:
```bash
git add scripts/autoloads/ExplorationEvents.gd scripts/autoloads/CombatEvents.gd
git add scenes/autoloads/ExplorationEvents.tscn scenes/autoloads/CombatEvents.tscn
git commit -m "Add ExplorationEvents and CombatEvents autoload buses"
```

---

## Task 3 — MovementComponent: emit step_taken

**What changes:** `MovementComponent` now accumulates distance traveled and emits `ExplorationEvents.step_taken` every `step_distance` units. This is the heartbeat that the encounter system listens to.

**Why distance, not time:** A step counter based on time would tick even when standing still. Distance means "you actually walked somewhere." It also naturally maps to footstep audio and VFX later.

**File:** Modify `scripts/characters/overworld/MovementComponent.gd`

- [ ] Add `step_distance` export and `_distance_accumulated` private variable at the top of the class (after the existing exports):

```gdscript
@export var step_distance: float = 1.0
var _distance_accumulated: float = 0.0
```

- [ ] In `_physics_process`, after the line `get_parent().position += move * speed * delta`, add the step accumulation:

```gdscript
var move_amount := (move * speed * delta).length()
_distance_accumulated += move_amount
if _distance_accumulated >= step_distance:
    _distance_accumulated -= step_distance
    ExplorationEvents.step_taken.emit()
```

The `_distance_accumulated -= step_distance` (not `= 0.0`) is intentional: it preserves any overshoot, keeping step rate accurate at any framerate.

- [ ] Run the game. Move the character and confirm `ExplorationEvents.step_taken` fires — add a temporary `Log.debug("step taken")` inside the emit block to verify, then remove it.

- [ ] Commit:
```bash
git add scripts/characters/overworld/MovementComponent.gd
git commit -m "MovementComponent: emit ExplorationEvents.step_taken on distance threshold"
```

---

## Task 4 — StepCounter

**What this is:** A simple node that listens to `ExplorationEvents.step_taken` and counts down. When the counter hits zero it emits `threshold_reached` and resets. The counter starts at 256 and decrements by a random amount (1–8) per step — this is the classic random encounter feel.

**File:**
- Create: `scripts/overworld/StepCounter.gd`
- Create: `scenes/overworld/StepCounter.tscn`

- [ ] Create `scripts/overworld/StepCounter.gd`:

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

func _on_step_taken() -> void:
    _counter -= randi_range(1, 8)
    if _counter <= 0:
        _counter = RESET_VALUE
        Log.info("StepCounter threshold reached, resetting to", RESET_VALUE)
        threshold_reached.emit()
```

- [ ] Create `scenes/overworld/StepCounter.tscn`: new scene, `Node` root named `StepCounter`, attach the script, save.

- [ ] Run the game and walk around. You should see `StepCounter threshold reached` appear in the Output panel roughly every 256 steps. Adjust `step_distance` on MovementComponent if thresholds fire too fast or slow.

- [ ] Commit:
```bash
git add scripts/overworld/StepCounter.gd scenes/overworld/StepCounter.tscn
git commit -m "Add StepCounter: counts steps via ExplorationEvents, emits threshold_reached"
```

---

## Task 5 — EncounterPool

**What this is:** Holds an array of `CombatConfig` resources and picks one using weighted random selection when asked. Each area gets its own `EncounterPool` with its own authored encounters.

**Weighted random:** Each `CombatConfig` has a `weight` value. The pool rolls a random number against the sum of all weights and walks down the list until it finds the winner. Higher weight = more likely. Adding a rare encounter just means giving it a low weight — no percentages to rebalance.

**Files:**
- Create: `scripts/overworld/EncounterPool.gd`
- Create: `scenes/overworld/EncounterPool.tscn`

- [ ] Create `scripts/overworld/EncounterPool.gd`:

```gdscript
class_name EncounterPool
extends Node

signal encounter_ready(config: CombatConfig)

@export var encounters: Array[CombatConfig] = []

func pick() -> void:
    if encounters.is_empty():
        Log.warn("EncounterPool.pick() called but encounters array is empty")
        return

    var total_weight: int = 0
    for c in encounters:
        total_weight += c.weight

    var roll: int = randi() % total_weight
    for c in encounters:
        roll -= c.weight
        if roll < 0:
            Log.info("EncounterPool picked:", c.resource_path)
            encounter_ready.emit(c)
            return

    # Fallback — floating point drift safety net
    encounter_ready.emit(encounters[-1])
```

- [ ] Create `scenes/overworld/EncounterPool.tscn`: new scene, `Node` root named `EncounterPool`, attach script, save.

- [ ] Commit:
```bash
git add scripts/overworld/EncounterPool.gd scenes/overworld/EncounterPool.tscn
git commit -m "Add EncounterPool: weighted random CombatConfig picker"
```

---

## Task 6 — EncounterManager

**What this is:** The thin glue node that lives on each map. It owns a `StepCounter` and an `EncounterPool` as children, and connects them: when `StepCounter` fires `threshold_reached`, it tells `EncounterPool` to pick. When `EncounterPool` fires `encounter_ready`, it emits on `CombatEvents`. That's the whole script.

**Files:**
- Create: `scripts/overworld/EncounterManager.gd`
- Create: `scenes/overworld/EncounterManager.tscn`

- [ ] Create `scripts/overworld/EncounterManager.gd`:

```gdscript
class_name EncounterManager
extends Node

@onready var step_counter: StepCounter = $StepCounter
@onready var encounter_pool: EncounterPool = $EncounterPool

func _ready() -> void:
    Log.info("EncounterManager ready")
    step_counter.threshold_reached.connect(_on_threshold_reached)
    encounter_pool.encounter_ready.connect(_on_encounter_ready)

func _on_threshold_reached() -> void:
    encounter_pool.pick()

func _on_encounter_ready(config: CombatConfig) -> void:
    CombatEvents.encounter_triggered.emit(config)
```

- [ ] Create `scenes/overworld/EncounterManager.tscn`:
  - Root: `Node` named `EncounterManager`, attach `EncounterManager.gd`
  - Add child: instance `StepCounter.tscn`, name it `StepCounter`
  - Add child: instance `EncounterPool.tscn`, name it `EncounterPool`
  - Save

- [ ] Commit:
```bash
git add scripts/overworld/EncounterManager.gd scenes/overworld/EncounterManager.tscn
git commit -m "Add EncounterManager: wires StepCounter → EncounterPool → CombatEvents"
```

---

## Task 7 — VitalsComponent

**What this is:** The component that tracks current HP, MP, and AP for a combat character. It reads its initial values from `CharacterSaveData` (players) or `CombatData.MaxHP/MaxMP` (enemies) at the start of each encounter, and resets between encounters.

**Files:**
- Create: `scripts/combat/VitalsComponent.gd`
- Create: `scenes/combat/components/VitalsComponent.tscn`

- [ ] Create `scripts/combat/VitalsComponent.gd`:

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

- [ ] Create `scenes/combat/components/VitalsComponent.tscn`: `Node` root named `VitalsComponent`, attach script, save. You'll need to create the `scenes/combat/components/` folder first.

- [ ] Commit:
```bash
git add scripts/combat/VitalsComponent.gd scenes/combat/components/VitalsComponent.tscn
git commit -m "Add VitalsComponent: cur_hp/mp/ap with setup() and reset()"
```

---

## Task 8 — Component stubs: TokenContainer + CombatInputComponent

**What these are:** Two components that need to exist in the scene tree now (so `CombatCharacter.tscn` can be fully assembled) but don't have any behaviour yet. A stub is a valid, complete script — it just doesn't do much. This is intentional: we're building the skeleton first.

**Files:**
- Create: `scripts/combat/TokenContainer.gd` + `scenes/combat/components/TokenContainer.tscn`
- Create: `scripts/combat/CombatInputComponent.gd` + `scenes/combat/components/CombatInputComponent.tscn`

- [ ] Create `scripts/combat/TokenContainer.gd`:

```gdscript
class_name TokenContainer
extends Node

# Holds active combat tokens for a character.
# Stub — full implementation in a future task.

func flush() -> void:
    Log.info("TokenContainer flushed (stub)")
```

- [ ] Create `scripts/combat/CombatInputComponent.gd`:

```gdscript
class_name CombatInputComponent
extends Node

# Handles player input during combat: action selection, targeting.
# Stub — full implementation in a future task.
```

- [ ] Create both `.tscn` files following the same pattern as Task 7.

- [ ] Commit:
```bash
git add scripts/combat/TokenContainer.gd scenes/combat/components/TokenContainer.tscn
git add scripts/combat/CombatInputComponent.gd scenes/combat/components/CombatInputComponent.tscn
git commit -m "Add TokenContainer and CombatInputComponent stubs"
```

---

## Task 9 — VisualComponent: combat adaptation

**What changes:** The existing `VisualComponent` (`scripts/characters/overworld/VisualComponent.gd`) connects to a `controller` node for movement signals. In combat, characters don't move — they just display an idle sprite. We need to make `controller` optional and add a `setup()` method so `CombatCharacter` can hand it a `SpriteFrames` resource.

**Important:** This is a targeted addition to an existing file — don't restructure or rename anything.

**File:** Modify `scripts/characters/VisualComponent.gd` (this is what `scenes/characters/VisualComponent.tscn` actually references — there is also a duplicate at `scripts/characters/overworld/VisualComponent.gd`, leave that one alone for now)

- [ ] Add a `setup()` method to `VisualComponent.gd`:

```gdscript
func setup(sprite_frames: SpriteFrames) -> void:
    sprite.sprite_frames = sprite_frames
    sprite.play("Idle_Down")
    Log.info("VisualComponent setup with sprite_frames")
```

- [ ] Guard the `controller` connections in `_ready()` so they're skipped when `controller` is null (combat use):

```gdscript
func _ready() -> void:
    Log.info("Initializing...")
    if controller == null:
        return
    controller.direction_changed.connect(_on_direction_changed)
    controller.run_toggled.connect(_on_run_toggled)
```

- [ ] Run the game. Overworld character movement should work exactly as before.

- [ ] Commit:
```bash
git add scripts/characters/overworld/VisualComponent.gd
git commit -m "VisualComponent: make controller optional, add setup() for combat use"
```

---

## Task 10 — CombatCharacter scene

**What this is:** The composed scene for a single combatant in combat — player or enemy. It assembles all the components built in Tasks 7–9. The root script is thin: it has an `initialize()` method that receives data and fans it out to each component.

**Files:**
- Create: `scripts/combat/CombatCharacter.gd`
- Create: `scenes/combat/CombatCharacter.tscn`

- [ ] Create `scripts/combat/CombatCharacter.gd`:

```gdscript
class_name CombatCharacter
extends Node3D

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var visual: VisualComponent = $VisualComponent
@onready var tokens: TokenContainer = $TokenContainer

# Called for player characters (reading from save data)
func initialize_player(data: PlayerData, save_data: CharacterSaveData) -> void:
    visual.setup(data.character_sprite)
    vitals.setup(save_data.cur_hp, save_data.cur_mp)
    Log.info("CombatCharacter (player) initialized:", data.character_name, vitals.cur_hp, vitals.cur_mp)

# Called for enemy characters (reading from base stats)
func initialize_enemy(data: EnemyData) -> void:
    visual.setup(data.character_sprite)
    vitals.setup(data.MaxHP, data.MaxMP)
    Log.info("CombatCharacter (enemy) initialized:", data.character_name, vitals.cur_hp, vitals.cur_mp)

func reset_for_combat() -> void:
    vitals.reset()
    tokens.flush()
```

- [ ] Create `scenes/combat/CombatCharacter.tscn` in the Godot editor:
  - Root: `Node3D` named `CombatCharacter`, attach `CombatCharacter.gd`
  - Add child: instance `scenes/combat/components/VitalsComponent.tscn`
  - Add child: instance the **existing** `scenes/characters/VisualComponent.tscn` — **leave `controller` export empty** (null = combat mode, the guard added in Task 9 handles this)
  - Add child: instance `scenes/combat/components/TokenContainer.tscn`
  - Add child: instance `scenes/combat/components/CombatInputComponent.tscn`
  - Save

- [ ] Commit:
```bash
git add scripts/combat/CombatCharacter.gd scenes/combat/CombatCharacter.tscn
git commit -m "Add CombatCharacter scene: assembled from VitalsComponent, VisualComponent, TokenContainer"
```

---

## Task 11 — CombatBackground

**What this is:** A focused node that owns the background visual and BGM player. When the CombatScene calls `swap()`, it swaps the texture and starts the new track. Nothing else touches this node.

**Files:**
- Create: `scripts/combat/CombatBackground.gd`
- Create: `scenes/combat/CombatBackground.tscn`

- [ ] Create `scripts/combat/CombatBackground.gd`:

```gdscript
class_name CombatBackground
extends Node

@onready var background_sprite: Sprite3D = $BackgroundSprite
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer

func swap(texture: Texture2D, stream: AudioStream) -> void:
    if texture != null:
        background_sprite.texture = texture
    if stream != null:
        bgm_player.stream = stream
        bgm_player.play()
    Log.info("CombatBackground swapped")
```

- [ ] Create `scenes/combat/CombatBackground.tscn`:
  - Root: `Node` named `CombatBackground`, attach script
  - Child: `Sprite3D` named `BackgroundSprite`
  - Child: `AudioStreamPlayer` named `BGMPlayer`
  - Save

- [ ] Commit:
```bash
git add scripts/combat/CombatBackground.gd scenes/combat/CombatBackground.tscn
git commit -m "Add CombatBackground: swaps background texture and BGM per encounter"
```

---

## Task 12 — PlayerSpawner + EnemySpawner

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
        if slot_data == null:
            continue
        _characters[i].initialize_player(slot_data.player_data, slot_data.save_data)
```

- [ ] Create `scripts/combat/EnemySpawner.gd`:

```gdscript
class_name EnemySpawner
extends Node

const CombatCharacterScene = preload("res://scenes/combat/CombatCharacter.tscn")

func initialize(enemy_slots: Array) -> void:
    clear()
    var slots = get_children()
    for i in enemy_slots.size():
        if i >= slots.size():
            break
        if enemy_slots[i] == null:
            continue
        var character: CombatCharacter = CombatCharacterScene.instantiate()
        slots[i].add_child(character)
        character.initialize_enemy(enemy_slots[i])

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

## Task 13 — CombatScene coordinator

**What this is:** The root of the combat scene. It does one thing: fan `initialize(config)` out to its three sub-nodes in the right order. It holds no logic itself.

**Files:**
- Create: `scripts/combat/CombatScene.gd`
- Create: `scenes/combat/CombatScene.tscn`

- [ ] Create `scripts/combat/CombatScene.gd`:

```gdscript
class_name CombatScene
extends Node

@onready var background: CombatBackground = $CombatBackground
@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner

func initialize(config: CombatConfig) -> void:
    Log.info("CombatScene initializing...")
    _reset_state()
    background.swap(config.background, config.bgm)
    player_spawner.initialize()
    enemy_spawner.initialize(config.enemy_slots)
    Log.info("CombatScene initialized")

func _reset_state() -> void:
    # Explicit state reset before every encounter.
    # See spec: "State Reset at CombatStart"
    player_spawner.reset_characters()
    enemy_spawner.clear()
```

- [ ] Add `reset_characters()` to `PlayerSpawner.gd`:

```gdscript
func reset_characters() -> void:
    for character in _characters:
        character.reset_for_combat()
```

- [ ] Create `scenes/combat/CombatScene.tscn`:
  - Root: `Node` named `CombatScene`, attach `CombatScene.gd`
  - Children: instance `CombatBackground.tscn`, `PlayerSpawner.tscn`, `EnemySpawner.tscn`
  - Save

- [ ] Commit:
```bash
git add scripts/combat/CombatScene.gd scenes/combat/CombatScene.tscn
git add scripts/combat/PlayerSpawner.gd
git commit -m "Add CombatScene coordinator: fans initialize(config) to sub-nodes"
```

---

## Task 14 — PartyManager autoload

**What this is:** The autoload that holds `GlobalSaveData` and exposes party members. For now it creates a hardcoded test party so we can verify the full pipe without needing save/load infrastructure.

**Files:**
- Create: `scripts/autoloads/PartyManager.gd`
- Create: `scenes/autoloads/PartyManager.tscn`

- [ ] Create `scripts/autoloads/PartyManager.gd`:

```gdscript
class_name PartyManager
extends Node

var save_data: GlobalSaveData = null

# Registry of all known PlayerData resources, keyed by character_ID.
# Populated at _ready from authored .tres files.
var _registry: Dictionary = {}

func _ready() -> void:
    Log.info("PartyManager ready")
    _load_registry()
    _load_save()

func _load_registry() -> void:
    # TODO: replace with a proper scan of the characters/ folder once
    # PlayerData .tres files exist. Hardcoded for now.
    pass

func _load_save() -> void:
    # TODO: load from disk. For now, create a stub save.
    save_data = GlobalSaveData.new()
    save_data.party_slots = ["", "", ""]
    Log.info("PartyManager using stub save data")

# Returns a Dictionary {player_data: PlayerData, save_data: CharacterSaveData},
# or null if the slot is empty or the character_ID has no registered PlayerData.
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

- [ ] Commit:
```bash
git add scripts/autoloads/PartyManager.gd scenes/autoloads/PartyManager.tscn
git commit -m "Add PartyManager autoload: holds GlobalSaveData, exposes get_slot()"
```

---

## Task 15 — ScreenFader

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
    - `fade_out`: animate `ColorRect.modulate.a` from `0.0` to `1.0` over 0.3s, last keyframe emits `ScreenFader.fade_out_done`
    - `fade_in`: animate `ColorRect.modulate.a` from `1.0` to `0.0` over 0.3s, last keyframe emits `ScreenFader.fade_in_done`
  - Save

- [ ] Commit:
```bash
git add scripts/core/ScreenFader.gd scenes/core/ScreenFader.tscn
git commit -m "Add ScreenFader: awaitable fade_out/fade_in via AnimationPlayer"
```

---

## Task 16 — GameManager FSM

**What this is:** The top-level game state machine. For now: two states (`OVERWORLD`, `COMBAT`), triggered by `CombatEvents.encounter_triggered`. It owns the transition sequence and holds a reference to the current overworld node (set by each map when it enters the tree).

**Files:**
- Create: `scripts/core/GameManager.gd`
- Modify: `scenes/core/game_manager.tscn`

- [ ] Create `scripts/core/GameManager.gd`:

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
    # Debug hotkey: press F1 to trigger combat with a blank config
    if event.is_action_pressed("debug_trigger_combat"):
        CombatEvents.encounter_triggered.emit(CombatConfig.new())

func _on_encounter_triggered(config: CombatConfig) -> void:
    if state != State.OVERWORLD:
        return
    state = State.COMBAT
    if current_overworld != null:
        current_overworld.process_mode = Node.PROCESS_MODE_DISABLED
    await fader.fade_out()
    combat_scene.process_mode = Node.PROCESS_MODE_INHERIT
    combat_scene.initialize(config)
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

## Task 17 — Register GameManager as autoload + wire a test map

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
  - On the `EncounterPool` child of `EncounterManager`, add at least one `CombatConfig` to its `encounters` array. Create a `CombatConfig` `.tres` file (`File → New Resource → CombatConfig`), set `weight = 10`, leave `enemy_slots` empty for now. Attach it to the array.
  - Add your existing overworld player character to the scene so `MovementComponent` can emit steps

- [ ] Set `Map_Test.tscn` as the main scene (`Project → Project Settings → Application → Run → Main Scene`).

- [ ] Commit:
```bash
git add scenes/overworld/Map_Test.tscn scripts/overworld/map_test.gd
git commit -m "Add Map_Test scene for end-to-end encounter trigger testing"
```

---

## Task 18 — End-to-end verification

**What to verify:**

- [ ] Run the game (F5). Check Output panel:
  - All autoloads log `ready` — GameManager, PartyManager, CombatEvents, ExplorationEvents
  - `StepCounter ready, counter = 256` appears
  - `EncounterManager ready` appears

- [ ] Walk the player character. After roughly 256 steps:
  - `StepCounter threshold reached, resetting to 256`
  - `EncounterPool picked: ...`
  - `CombatScene initializing...`
  - Fade to black, combat scene appears (blank for now — no background asset yet)
  - `CombatScene initialized` in log

- [ ] Press F1 (debug hotkey):
  - Same flow triggers immediately without walking

- [ ] Verify the enemy/player Log output:
  - If `PartyManager` has no party data yet, `PlayerSpawner` will skip slots silently (the `if slot_data == null: continue` guard). That's expected — party data wiring comes later.

- [ ] When everything is visible and logging correctly, final commit:
```bash
git add .
git commit -m "End-to-end combat transition pipe: overworld → fade → combat scene init"
```

---

## What Comes Next (out of scope for this plan)

- Populating `PartyManager` with real `PlayerData` `.tres` files and `CharacterSaveData`
- Authored `CombatConfig` `.tres` files with real enemy compositions
- Return to overworld: call `GameManager.end_combat()` after a trigger (e.g. debug key)
- `CharacterSaveData` writeback at `CombatEnd`
- `TurnOrderManager` + combat FSM (the actual fight)
