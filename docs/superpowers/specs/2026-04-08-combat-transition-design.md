# Combat Scene Transition & Data Flow — Design Spec
**Date:** 2026-04-08
**Scope:** Overworld → combat transition, actor initialization, combatant display. No combat loop.

---

## Scope

### In scope
- `GameManager` autoload — thin FSM (`OVERWORLD` / `COMBAT` states), owns screen fades and transition orchestration
- `PartyManager` autoload — holds `GlobalSaveData`, exposes party slots
- `CombatEvents` autoload — combat domain event bus (signals only)
- `ExplorationEvents` autoload — exploration domain event bus (signals only, `step_taken` for now)
- `EncounterManager` scene — lives on each map, composed of `StepCounter` + `EncounterPool`
- `CombatConfig` resource — maps enemy slots to `EnemyData`, carries background + BGM
- `GlobalSaveData` resource — party slot assignments + per-character `CharacterSaveData`
- Persistent `CombatScene` — always in tree, disabled when inactive, composed of `CombatBackground` + `PlayerSpawner` + `EnemySpawner`
- `combat_character` — composed of `VisualComponent`, `VitalsComponent`, `CombatInputComponent`, `TokenContainer`
- `MovementComponent` emits `ExplorationEvents.step_taken` on distance threshold
- Debug hotkey to trigger combat on demand
- Print combatant names + HP/MP on combat init

### Out of scope
- Combat loop, turn order, action menus, skills
- Post-combat flow (XP, loot, return)
- AI turns, tokens, reactions
- Footstep audio, dust VFX (will connect to `step_taken` later)
- FANTASIAN-style encounter deferral
- Encounter indicator bar

---

## Autoloads

Four autoloads, all registered as `.tscn` files per project convention.

```
GameManager       — thin FSM, transition orchestration, owns ScreenFader child
PartyManager      — holds GlobalSaveData, exposes get_slot(index)
CombatEvents      — combat domain signals only, no logic
ExplorationEvents — exploration domain signals only, no logic
```

### CombatEvents signals (initial)
```gdscript
signal encounter_triggered(config: CombatConfig)
```

### ExplorationEvents signals (initial)
```gdscript
signal step_taken
```

---

## Scene & Node Structure

### GameManager.tscn
```
GameManager
  ├── ScreenFader       ← full-screen ColorRect + AnimationPlayer
  │                        exposes fade_out() / fade_in() as awaitable
  └── CombatScene.tscn  ← permanent child, process_mode toggled per state
```

### CombatScene.tscn
```
CombatScene
  ├── CombatBackground  ← owns background visual + BGM AudioStreamPlayer
  │                        swap(texture: Texture2D, stream: AudioStream)
  ├── PlayerSpawner     ← owns PlayerSlots, reads PartyManager, initializes
  │     ├── Slot1         permanent player combat_characters
  │     ├── Slot2
  │     └── Slot3
  └── EnemySpawner      ← owns EnemySlots, spawns/frees enemies per CombatConfig
        ├── Slot1
        ├── Slot2
        ├── Slot3
        ├── Slot4
        ├── Slot5
        └── Slot6
```

All slots are `Node3D` with authored world positions. Player `combat_character` nodes are permanent children of `PlayerSlots` — initialized at game load, never freed. Enemy `combat_character` nodes are instantiated into `EnemySlots` at `CombatStart` and freed at `CombatEnd`.

### combat_character.tscn
```
combat_character
  ├── VisualComponent       ← owns AnimatedSprite3D, handles visuals only
  ├── VitalsComponent       ← cur_hp, cur_mp, cur_ap + mutation methods
  ├── CombatInputComponent  ← combat-specific input (not PlayerInputComponent)
  └── TokenContainer        ← active tokens, add/remove/tick
```

### Map scene (one per overworld area)
```
Map_Forest.tscn
  ├── Terrain / props
  ├── Player (overworld character)
  └── EncounterManager
        ├── StepCounter     ← connects to ExplorationEvents.step_taken,
        │                      decrements by randi_range(1,8) per step,
        │                      emits threshold_reached when counter hits 0
        └── EncounterPool   ← holds Array[CombatConfig], picks one on
                               threshold_reached, emits CombatEvents.encounter_triggered(config)
```

`EncounterManager.gd` is a thin connector: wires `StepCounter.threshold_reached` → `EncounterPool.pick()`.

---

## Data Resources

### CombatConfig (.tres)
```gdscript
class_name CombatConfig
extends Resource

@export var enemy_slots: Array  # Array[EnemyData], index 0–5 = EnemySlot1–6, null = empty slot
@export var background: Texture2D
@export var bgm: AudioStream
```

### GlobalSaveData (.tres / save file)
```gdscript
class_name GlobalSaveData
extends Resource

@export var party_slots: Array[String]                  # 3 character_IDs, ordered by slot
@export var roster: Dictionary                          # character_ID → CharacterSaveData
```

`character_ID` (already on `CharacterData`) is the key bridging `GlobalSaveData` ↔ authored `PlayerData` `.tres` files. `PartyManager` maintains an `{ id → PlayerData }` registry loaded at startup.

### CharacterSaveData — source of truth for runtime stats
`VitalsComponent` reads from `CharacterSaveData` at `CombatStart`. Writes back at `CombatEnd`. `CharacterSaveData` is always the canonical state — `VitalsComponent` is transient.

---

## MovementComponent — step_taken

`MovementComponent` accumulates distance traveled and emits `ExplorationEvents.step_taken` when a threshold is crossed. The threshold is an exported float, tunable per character.

```gdscript
signal step_taken  # NOT on MovementComponent — emitted via ExplorationEvents

@export var step_distance: float = 1.0
var _distance_accumulated: float = 0.0

# in _physics_process, after applying movement:
_distance_accumulated += move_amount
if _distance_accumulated >= step_distance:
    _distance_accumulated -= step_distance
    ExplorationEvents.step_taken.emit()
```

`StepCounter` connects to `ExplorationEvents.step_taken` in `_ready()`. Future listeners (footstep audio, dust VFX) connect independently — no changes to `MovementComponent`.

---

## Data Flow

### Trigger → Transition

```
MovementComponent._physics_process()
  → distance threshold crossed
  → ExplorationEvents.step_taken.emit()

StepCounter._on_step_taken()
  → counter -= randi_range(1, 8)
  → if counter <= 0: threshold_reached.emit()

EncounterPool._on_threshold_reached()
  → pick CombatConfig from encounters[]
  → CombatEvents.encounter_triggered.emit(config)

GameManager._on_encounter_triggered(config)
  → state = COMBAT
  → await ScreenFader.fade_out()
  → overworld node process_mode = DISABLED
  → CombatScene.initialize(config)
  → await ScreenFader.fade_in()
```

**Debug hotkey** (in GameManager or a dev tool node):
```gdscript
# Bypasses StepCounter entirely
CombatEvents.encounter_triggered.emit(debug_config)
```

### CombatScene.initialize(config)

```
CombatBackground.swap(config.background, config.bgm)

PlayerSpawner.initialize()
  for i in 3:
    var slot = PartyManager.get_slot(i)       # returns {PlayerData, CharacterSaveData}
    combat_characters[i].initialize(slot.player_data, slot.save_data)
      → VitalsComponent.setup(save_data.hp, save_data.mp)
      → VisualComponent.setup(player_data.character_sprite)
      → Log.info(player_data.character_name, save_data.hp, save_data.mp)

EnemySpawner.initialize(config.enemy_slots)
  for i in config.enemy_slots.size():
    if config.enemy_slots[i] == null: continue
    var enemy = combat_character.instantiate()
    enemy.initialize(config.enemy_slots[i])
      → VitalsComponent.setup(enemy_data base hp/mp)
      → VisualComponent.setup(enemy_data.character_sprite)
      → Log.info(enemy_data.character_name, hp, mp)
    EnemySlots.get_child(i).add_child(enemy)
```

### CombatEnd (stub)

```
GameManager.end_combat()
  → await ScreenFader.fade_out()
  → CombatScene process_mode = DISABLED
  → EnemySpawner.clear()          ← frees all enemy combat_characters
  → overworld process_mode = ENABLED
  → await ScreenFader.fade_in()
  → state = OVERWORLD
```

No `CharacterSaveData` writeback yet — that belongs to the `CombatEnd` FSM state.

---

## State Reset at CombatStart

Persistent nodes carry state between encounters. The following must be reset explicitly inside `CombatScene.initialize()` before anything else:

| Component | What resets |
|---|---|
| `VitalsComponent` | AP reset to 3; HP/MP read fresh from `CharacterSaveData` |
| `TokenContainer` | All tokens flushed |
| `TurnOrderManager` | CT values zeroed (post-MVP, noted for when it exists) |
| UI state | Command menus, cursors, targeting state cleared (post-MVP) |

Being explicit here is the entire point. Nothing assumes it resets itself.

---

## What Is Not Designed Yet

- `TurnOrderManager` — exists in concept, not in scope for this slice
- Post-combat XP / loot / `CharacterSaveData` writeback
- Random encounter rate variation, weighted pools
- `CombatFSM` / `UIFSM` — full turn loop
- `GameManager` states beyond `OVERWORLD` / `COMBAT` (DIALOGUE, WORLD_MAP, etc.)
