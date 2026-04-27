# Area / Zone Architecture — Design Spec
**Date:** 2026-04-25
**Status:** AGREED — ready for implementation plan
**Scope:** The structural layer that sits above individual scenes — how the game world is decomposed into Areas and Zones, how Zones contain both exploration and combat, how transitions between Zones and into/out of combat are wired, and where the persistent player lives. Does not cover the World Map (postponed), save/load, or zone-state persistence between visits.

---

## What This Is

The combat scene template (2026-04-21) was designed bottom-up. It works, but it sits in a vacuum — there is no proper "place" that a Zone declares its combat configuration, and the current `EncounterManager` doubles as both data container and orchestrator while living awkwardly inside `main.tscn`. This spec defines the layer above: **what an Area is, what a Zone is, what a Zone contains, and how they're loaded and stitched together.**

The goal is a structure that scales from "one test zone" today to "Northern Forest containing four zones with a forest cave inside it" later, without any architectural shift — only authoring more zones.

---

## Architecture Overview

Three levels of structure, top to bottom:

| Level | What it is | Persistence |
|---|---|---|
| **World Map** | Graph of nodes you travel between, FF-Tactics style | Out of scope for this spec |
| **Area** | A logical region (e.g., Northern Forest) — a collection of Zones, a name, a world map identity | A `Resource` (`.tres`). Not a scene. |
| **Zone** | The actual playable space (e.g., ForestPath, Clearing, ForestCave) — has geometry, lighting, BGM, NPCs, combat config | A `PackedScene` (`.tscn`). Loaded by GameManager. |

**Areas don't own gameplay nodes.** They're pure data — a name, an entry zone reference, a graph of which zones connect to which via which exits. Areas exist for the world map layer to reason about ("you're in Northern Forest"). They don't get instanced into the scene tree.

**Zones are where everything lives.** Geometry, lighting, NPCs, items, triggers, puzzles, combat configuration — all per-zone. Zones are what GameManager loads and unloads.

### Why per-Zone lighting (not per-Area)

A forest area that contains a cave is normal JRPG geography. If lighting were shared at the Area level, ForestPath and ForestCave would have to share visual identity — forcing world map transitions for biome shifts within a logical region. Bad for gameplay.

Putting `WorldEnvironment` (and optionally `DirectionalLight3D`) at the Zone level means:
- Visual consistency within an Area is achieved by zones referencing the same `Environment.tres` resource (DRY through resources, not through node ownership).
- Outliers (the cave inside the forest) just declare different settings.
- Combat inherits the zone's atmosphere automatically — when the zone is process-disabled during combat, render nodes (`WorldEnvironment`, plus any `DirectionalLight3D` if the zone has one) keep rendering. Same ambient, same fog, same sky. No extra wiring.

### Visual style and what this means for lighting

The art direction is flat, unlit pixel art (Breath of Fire IV / PSX-era JRPG reference). Materials use unlit/full-bright shading; shading is "baked into" the texture art. As a consequence:

- `WorldEnvironment` is **required** in every zone. It owns ambient tint, background colour/sky, fog, glow, post-processing. These still matter for atmosphere even when nothing is lit.
- `DirectionalLight3D` is **optional** and not part of the default zone template. Most zones won't have one. A zone that wants atmospheric directional light (a cathedral with godrays, a lit forge) can add its own. By default, ambient from `WorldEnvironment` is enough.
- The "lighting angle mismatch between exploration and combat" concern doesn't apply — there's no directional angle by default. Combat and exploration look identical because both are unlit. This is intentional, not oversight.

### Combat environment scenes are geometry-only (hard rule)

A combat environment scene (e.g., `forest_combat.tscn`, instantiated into `CombatScene/EnvironmentMount`) **must not** contain its own `WorldEnvironment` or `DirectionalLight3D`. Two `WorldEnvironment` nodes in the same tree produce undefined ordering behaviour; two `DirectionalLight3D`s contribute additively. The zone's render nodes are what light combat — combat envs are mesh, collision, and dressing only. A combat stage that genuinely needs different lighting (rare) can override deliberately, but the default is "zone renders combat."

---

## The Area Resource

```gdscript
class_name Area
extends Resource

@export var area_name: String
@export var entry_zone: PackedScene
@export var zones: Array[ZoneConnection]   # zone graph
@export var world_map_position: Vector2    # for future world map UI
```

`ZoneConnection` describes how zones link. Concrete shape can be deferred — minimum viable is "this exit in zone X leads to zone Y at spawn point Z."

**Areas are authored as `.tres` files** under `resources/areas/`. They contain no gameplay logic — just the navigation data the world map and GameManager need to reason about the region.

---

## The Zone Scene Anatomy

A Zone scene has a fixed top-level structure. Authoring a new zone means duplicating the template, populating the children, and configuring exports.

```
Zone (e.g., NorthernForest_ForestPath.tscn)
├── System
│   ├── WorldEnvironment
│   ├── DirectionalLight3D               ← OPTIONAL, not in default template
│   └── Camera3D                         ← targeted by player's RemoteTransform3D
├── SpawnPoints                          ← container, named Marker3D children
├── NPCs                                 ← container, holds NPC instances
├── Items                                ← container, holds item placements
├── Triggers                             ← container, holds Area3D trigger volumes (incl. ZoneExits)
├── Puzzles                              ← container, holds puzzle scenes
├── Exploration
│   ├── ExplorationEnvironment           ← PackedScene holder (zone geometry)
│   └── ExplorationBGM                   ← AudioStream holder
└── Combat
    ├── StepCounter
    ├── EncounterPool
    ├── CombatEnvironment                ← PackedScene holder (combat stage)
    └── CombatBGM                        ← AudioStream holder
```

### Container responsibilities

| Container | Owns | Script behaviour |
|---|---|---|
| `System` | Persistent zone infrastructure (env, optional light, camera) | None — pure node holder |
| `SpawnPoints` | Named `Marker3D` nodes — entry positions for the player pawn | None — pure node holder, looked up by name on zone load |
| `NPCs` | NPC scene instances placed in the zone | Container script (lifecycle hooks for NPCs as that system grows) |
| `Items` | Chests, pickups, key items | Container script (spawn/despawn, flag-driven visibility) |
| `Triggers` | `Area3D` volumes — zone exits, cutscene zones, scripted encounter triggers | Container script |
| `Puzzles` | Puzzle scene instances | Container script |
| `Exploration` | `ExplorationEnvironment`, `ExplorationBGM` | On zone enter: instantiate environment scene, play BGM |
| `Combat` | `StepCounter`, `EncounterPool`, `CombatEnvironment`, `CombatBGM` | Listen to `StepCounter.threshold_reached` → pick from `EncounterPool` → emit `CombatEvents.encounter_triggered` with composition + env + bgm. **Wandering encounters only.** |

The `Combat` container is the renamed/relocated `EncounterManager` from current code. Same children, same orchestration logic — moved into the Zone, sitting as a sibling of `Exploration`.

### Why "Exploration" earns its container despite being thin

It currently holds two children (`ExplorationEnvironment`, `ExplorationBGM`). That's lighter than `Combat` but the symmetry has cognitive value — the duology between exploration mode and combat mode reads naturally in the scene tree. Both are mode-specific assets in their own subtree.

### Why content (NPCs/Items/Triggers/Puzzles) sits at zone level, not inside `Exploration`

"Exploration" is a gamestate label, not a structural one. NPCs, items, triggers, and puzzles are zone content — they exist regardless of mode. A trigger could fire after combat ends. An item could be placed but only become collectible once a flag flips. Putting them inside `Exploration` would conflate "things in the world" with "things visible during exploration mode." Flat at zone level is more honest.

---

## Combat Trigger Sources

Combat can be initiated by two distinct sources, each with its own signal. Both go through the same combat-load code path in GameManager, but the split exists so divergent behaviour (e.g., "WARNING!" sting before bosses, no-flee flag, different fade timing) can be added without retrofitting.

| Signal | Source | Use case |
|---|---|---|
| `CombatEvents.encounter_triggered(composition, environment, bgm)` | The Combat container in the active zone, fired when `StepCounter.threshold_reached` | Wandering encounters — random, weighted from the zone's `EncounterPool` |
| `CombatEvents.scripted_encounter_triggered(composition, environment, bgm)` | Anywhere — boss trigger volumes in `Triggers`, NPCs that initiate fights, story event nodes | Boss fights, story battles, NPC-initiated combat |

The Combat container is the *only* source for `encounter_triggered`. Scripted sources fire `scripted_encounter_triggered` directly with their own bundle — they don't go through the Combat container, don't read from `EncounterPool`, and can supply any composition/environment/BGM they want (often boss-specific).

GameManager listens to both and runs the same combat-load sequence for now. The signals diverging today is structural preparation for behavioural divergence later.

---

## Spawn Points and Zone Connections

Each zone declares its possible entry positions as named `Marker3D` nodes inside the `SpawnPoints` container. Each connection from another zone is wired by paired authoring on both sides.

### Per-zone authoring

Every zone has at minimum:
- A `&"default"` spawn point — used when entering from the world map, or as a fallback when a transition doesn't specify a target.
- One `&"from_<other_zone_name>"` spawn point per incoming zone connection.

Example for ForestPath connected to Clearing:

```
ForestPath/
├── SpawnPoints/
│   ├── default                  ← Marker3D, where player appears from world map
│   └── from_clearing            ← Marker3D, where player appears coming from Clearing
└── Triggers/
    └── ToClearing               ← ZoneExit: target_zone=Clearing.tscn, target_spawn_point=&"from_forest_path"
```

And on the other side:

```
Clearing/
├── SpawnPoints/
│   ├── default                  ← Marker3D, world-map entry
│   └── from_forest_path         ← Marker3D, where player appears coming from ForestPath
└── Triggers/
    └── ToForestPath             ← ZoneExit: target_zone=ForestPath.tscn, target_spawn_point=&"from_clearing"
```

### Lookup mechanism

`spawn_points.get_node_or_null(name)` — direct named lookup, no recursion. Cheap, unambiguous.

### Failure modes

- **Spawn point not found:** GameManager logs `Log.error("Spawn point not found", name)` and falls back to `Vector3.ZERO`. The game continues — typos are visible in logs but don't crash. This is the dev-friendly behaviour; consider tightening to a hard error before release.
- **No `SpawnPoints` container:** the zone is malformed. `Log.error` and fall back to origin.

### World-map exit handling

Deferred to the world map spec. Conceptually, a zone exits "outwards" via either a dedicated `ToWorldMap` trigger or by walking out of the entry zone — but the world map itself isn't part of this spec, so this is unspecified for now.

---

## Lifecycle and Transitions

### Zone Load (entering an Area, or after world map travel)

1. Set `state = TRANSITIONING`. From here until step 9, all event handlers ignore incoming signals.
2. GameManager reads the target `Area` resource → finds `entry_zone`.
3. Fade out via `ScreenFader`.
4. Free the current zone (if any). `queue_free()` is enough — children unload recursively.
5. Instantiate the new zone, add as child of `CurrentZone` slot under GameManager.
6. Lazily instantiate the player pawn if it doesn't exist yet (first zone load only). Persistent thereafter.
7. Look up the target spawn point in `Zone/SpawnPoints/` by name. Place the player pawn at that marker's `global_position`.
8. Update the player's `RemoteTransform3D.remote_path` to point at the new zone's `System/Camera3D`.
9. Fade in.
10. Set `state = OVERWORLD`.

Same code path runs for "boot from main menu into first zone" and "zone-to-zone transition" — only difference is whether the pawn already exists.

### Zone-to-Zone Transitions

Triggered by a `ZoneExit` node living in the zone's `Triggers` container:

```gdscript
class_name ZoneExit
extends Area3D

@export var target_zone: PackedScene
@export var target_spawn_point: StringName  # named entry point in target zone

func _on_body_entered(body: Node) -> void:
    if body.is_in_group("player"):
        ExplorationEvents.zone_exit_requested.emit(target_zone, target_spawn_point)
```

GameManager listens for `zone_exit_requested` and runs the same load sequence as above, placing the player at the named spawn point in the new zone.

### Combat Trigger and End

`CombatScene` is no longer a permanent disabled child of GameManager. It's instantiated on demand:

```gdscript
const CombatSceneTemplate: PackedScene = preload("res://scenes/combat/combat_scene.tscn")
var _current_combat: CombatScene = null

func _on_encounter_triggered(composition, environment, bgm) -> void:
    state = Enums.GameState.TRANSITIONING
    await screen_fader.fade_out()
    _current_combat = CombatSceneTemplate.instantiate()
    add_child(_current_combat)
    _current_combat.initialize(composition, environment, bgm)
    current_zone.process_mode = Node.PROCESS_MODE_DISABLED
    _pawn.process_mode = Node.PROCESS_MODE_DISABLED   # freeze pawn during combat
    await screen_fader.fade_in()
    state = Enums.GameState.COMBAT

func end_combat() -> void:
    state = Enums.GameState.TRANSITIONING
    await screen_fader.fade_out()
    _current_combat.queue_free()
    _current_combat = null
    current_zone.process_mode = Node.PROCESS_MODE_INHERIT
    _pawn.process_mode = Node.PROCESS_MODE_INHERIT
    if _overworld_camera != null:
        _overworld_camera.make_current()
    await screen_fader.fade_in()
    state = Enums.GameState.OVERWORLD
```

This makes combat lifecycle symmetric with zone lifecycle — both load on demand, both free on end. The `cleanup()` method previously added to `CombatScene` becomes unnecessary; `queue_free()` recursively frees all children.

**Pawn freezing is critical.** The pawn lives under GameManager, not inside the zone. Disabling the zone via `PROCESS_MODE_DISABLED` does **not** affect the pawn — its `PlayerInputComponent` would keep reading input, `MovementComponent` would keep running, `RemoteTransform3D` would keep writing to the (now-inactive) overworld camera. Without the explicit pawn freeze, the player drifts in world space behind the combat screen and ends up in a surprise location when combat ends. One line, prevents a six-months-from-now bug.

### The TRANSITIONING State

Zone loads and combat enter/exit are multi-frame sequences (fade out → unload/load → fade in). During those windows, input must not produce new transitions or the user can stack them by mashing buttons during a fade.

`TRANSITIONING` is a fourth FSM state, entered at the start of any fade-out and exited only after the corresponding fade-in completes. All event handlers that initiate transitions guard on it:

```gdscript
func _on_encounter_triggered(...) -> void:
    if state != Enums.GameState.OVERWORLD:
        return
    # ... transition begins ...

func _on_zone_exit_requested(...) -> void:
    if state != Enums.GameState.OVERWORLD:
        return
    # ... transition begins ...

func _on_scripted_encounter_triggered(...) -> void:
    if state != Enums.GameState.OVERWORLD:
        return
    # ... transition begins ...
```

This guards against:
- Walking into a `ZoneExit` trigger while a previous zone-to-zone transition is still fading.
- Combat triggering during a zone fade.
- A second encounter firing during the combat-end fade.
- Any "I mashed buttons during a screen transition" class of bug.

Cheap, noisy in absence (you'd notice transitions stacking immediately in dev), and prevents a category of intermittent bugs that are notoriously hard to reproduce.

### Player Persistence Across Transitions

The overworld character pawn (`overworld_character.tscn`) lives as a child of GameManager, not inside any zone. It persists across all transitions. Zone loads place it at the appropriate entry point; combat transitions disable the zone but leave the pawn in place (it's not part of the zone tree).

The existing component composition inside `overworld_character.tscn` (`PlayerInputComponent`, `MovementComponent`, `VisualComponent`) is **unchanged**. The character scene file is preserved as-is — only its parent in the runtime tree changes. GameManager preloads it as a `PackedScene` constant and instantiates it lazily on first zone load:

```gdscript
const OverworldPawnTemplate: PackedScene = preload("res://scenes/characters/overworld_character.tscn")
var _pawn: Node3D = null
```

**Pawn freezing during combat:** because the pawn lives under GameManager (not inside the zone), disabling the zone does not freeze the pawn. GameManager explicitly toggles `_pawn.process_mode` to `PROCESS_MODE_DISABLED` on combat enter and `PROCESS_MODE_INHERIT` on combat end. See the Combat Trigger and End section above for the exact sequence.

Party data (HP, MP, inventory, levels, mnemonics) lives in `PartyManager` (autoload), as it does today. The pawn is the spatial representation; PartyManager owns the data.

---

## Camera

The exploration camera lives in the Zone, anchored to the player via `RemoteTransform3D`:

- `Camera3D` is a child of `Zone/System`. Each zone authors its own camera config (orthographic size, rotation, offset) — different zones may want different framing.
- The persistent player pawn carries a `RemoteTransform3D` child. Each frame, `RemoteTransform3D` copies its global transform to whatever node it's pointed at.
- The pawn persists across zones, but the camera does not. So `remote_path` cannot be authored in the editor — it must be re-set at runtime on every zone load. After GameManager finishes loading a zone and placing the player, it sets the player's `RemoteTransform3D.remote_path` to the new zone's `System/Camera3D`. From that frame on, the camera follows.

This is Godot's idiomatic answer to the Cinemachine "virtual camera with follow target" pattern — one node, one runtime assignment per zone, no per-frame scripting needed.

The combat camera stays inside `combat_scene.tscn` (per the 2026-04-21 spec). When combat instantiates, its camera calls `make_current()`; on combat end, GameManager calls `make_current()` on the saved overworld camera reference.

---

## BGM Behaviour

Combat enters and exits use the **stop-and-restart** pattern:

- **Combat enter:** the zone's `ExplorationBGM` stops. The combat scene's `BGMPlayer` plays the encounter's BGM stream from the top, looping.
- **Combat exit:** the combat `BGMPlayer` is freed along with `_current_combat`. GameManager restarts the zone's `ExplorationBGM` from the top.

This is the classic SNES-era JRPG behaviour. No infrastructure for pause/resume position tracking, no crossfading. If the audio feel becomes too repetitive in playtesting (frequent encounters → exploration BGM constantly restarting), a follow-up spec can introduce position-resume or crossfade.

Zone-to-zone transitions inherit the same pattern by default: the old zone's BGM stops with the zone, the new zone's BGM plays from the top.

Cross-zone BGM continuity (e.g., the same theme persisting across multiple forest zones without restarting) requires a session-level BGM manager that survives zone unload — out of scope for this spec.

---

## GameManager Scope

`GameManager` is the session-level orchestrator. Its responsibilities after this design lands:

- `ScreenFader` (transition visuals)
- `CombatSceneTemplate` constant + `_current_combat` instance reference
- `OverworldPawnTemplate` constant + `_pawn` instance reference
- `CurrentZone` slot (where the active zone lives — plain `Node`, just a stable parent path)
- High-level state machine: `MAINMENU` / `OVERWORLD` / `COMBAT` / `TRANSITIONING`
- Handlers for cross-system events: `encounter_triggered`, `scripted_encounter_triggered`, `zone_exit_requested`, combat end — all guard on state before acting
- BGM coordination across zone and combat transitions

It does **not** own:
- Party data (PartyManager autoload owns this)
- Combat logic (CombatScene owns this)
- Encounter picking (the Combat container in each Zone owns this)
- Zone-internal logic (each Zone owns its own children)

A rename to `Session` or `Director` would communicate the scope better, but is optional — the existing name works as long as scope is held. **Decision: keep `GameManager` for now, audit later if it starts collecting unrelated concerns.**

---

## Out of Scope

- **World Map.** The structural placeholder exists (Area resource has `world_map_position`), but the world map UI/scene/navigation is a separate spec.
- **Save / load.** PartyManager already handles party data persistence. Saving "current zone + player position" is its own design.
- **Zone-state persistence.** If you leave the Clearing and come back, are the chests still empty? Are NPCs in their post-conversation state? This requires a flag/state autoload referenced by zone content. Out of scope here — content nodes will read from such an autoload when the system arrives.
- **Multi-character party visualization.** The overworld pawn shows the lead character only (current behaviour). Showing a follow-train of party members is future work.
- **Reactive content.** "This NPC only appears after quest X" — handled by the NPC node checking flags on `_ready()` once a flag system exists. The placement still lives in the zone scene; visibility is runtime-driven.

---

## Migration Notes

The current codebase already implements much of this design under different names. The migration is mostly rename + relocate, not invent.

**What stays:**
- `CombatBGM`, `CombatEnvironment`, `EncounterPool`, `StepCounter` — keep their scripts and `.tscn`s as-is, they're already correct single-responsibility holders.
- `EncounterPool.entries` override pattern (via `[editable path]` in the parent scene) — keeps working, just on a renamed parent.
- `PartyManager`, `CombatEvents`, `ExplorationEvents`, `Log` autoloads — unchanged.
- `combat_scene.tscn` and `CombatScene.gd` — unchanged in structure, `cleanup()` method becomes obsolete and gets removed.

**What changes:**
- `EncounterManager` (node + script + `.tscn`) → renamed to `Combat` (`combat.gd`, `combat.tscn`). Same logic, new identity.
- `EncounterManager` location: `Main/System/EncounterManager` → `Zone/Combat`. It's now a sibling of `System`, not inside it.
- `main.tscn` → restructured into a proper Zone scene matching the template. Acts as the test zone for now. Eventually retired in favour of named zones (`NorthernForest_ForestPath.tscn`).
- `overworld_character` → moves out of the test zone, lives as a child of GameManager.
- `CameraRig/Camera3D` in `main.tscn` → moves into `Zone/System`.
- `CombatScene` → no longer a permanent child of GameManager; instantiated on demand via the new pattern documented above.
- `_overworld_camera` save/restore in GameManager → still needed when ending combat (camera reclaims). When loading a new zone, the new zone's camera will `make_current()` itself.

**What's new:**
- `Area` resource class and one example `.tres` for the test region.
- `Exploration` container (script + `.tscn`) — symmetrical partner to `Combat`.
- `ExplorationEnvironment`, `ExplorationBGM` (scripts + `.tscn`s) — mirror their combat counterparts.
- `ZoneExit` scene — `Area3D` with `target_zone: PackedScene` and `target_spawn_point: StringName` exports, fires `ExplorationEvents.zone_exit_requested`.
- `ExplorationEvents.zone_exit_requested(target_zone, spawn_point)` signal.
- `CombatEvents.scripted_encounter_triggered(composition, environment, bgm)` signal — for boss fights, story battles, NPC-initiated combat.
- `SpawnPoints` container (a plain `Node` with named `Marker3D` children) authored per zone. Looked up by `StringName` on zone load.
- Zone loading code in GameManager — handles fade, free old zone, instantiate new, place pawn at spawn point, rebind camera.
- Lazy player pawn instantiation in GameManager via `OverworldPawnTemplate` preloaded constant.
- `RemoteTransform3D` child added to `overworld_character.tscn` (or set up at runtime) — its `remote_path` is reassigned per zone load.

**Verification step in the implementation plan:**
The "process-disabled zone keeps rendering its `WorldEnvironment`" assumption is load-bearing for this whole architecture. The implementation plan must start with a small spike that confirms this behaviour in Godot 4.6 before any rename/migration work begins. If render nodes don't behave as expected under `PROCESS_MODE_DISABLED`, the design needs revisiting.

**Verification result: PASSED (2026-04-27)**
Spike scene `scenes/spikes/process_disabled_render_test.tscn` — a `WorldEnvironment` + `DirectionalLight3D` nested under a plain `Node` (`EnvWrapper`), with a lit cube in view. After 5 seconds, `EnvWrapper.process_mode = PROCESS_MODE_DISABLED` was set at runtime. The cube's ambient tint and directional shading were completely unchanged. Render nodes keep rendering regardless of process mode on their ancestor. Architecture proceeds as designed.

**Implementation order is plan territory, not spec.** A separate implementation plan will sequence the migration so each step is testable in Godot before moving on.
