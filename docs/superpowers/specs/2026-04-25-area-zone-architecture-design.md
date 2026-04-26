# Area / Zone Architecture — Design Spec
**Date:** 2026-04-25
**Status:** DRAFT — pending review
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

Putting `WorldEnvironment` and `DirectionalLight3D` at the Zone level means:
- Visual consistency within an Area is achieved by zones referencing the same `Environment.tres` resource (DRY through resources, not through node ownership).
- Outliers (the cave inside the forest) just declare different settings.
- Combat inherits the zone's lighting automatically — when the zone is process-disabled during combat, render nodes (`WorldEnvironment`, `DirectionalLight3D`) keep rendering. Combat in the cave is dark; combat in the clearing is bright. No extra wiring.

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
│   ├── DirectionalLight3D
│   └── Camera3D                         ← targeted by player's RemoteTransform3D
├── NPCs                                 ← container, holds NPC instances
├── Items                                ← container, holds item placements
├── Triggers                             ← container, holds Area3D trigger volumes
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
| `System` | Persistent zone infrastructure (lighting, env, camera) | None — pure node holder |
| `NPCs` | NPC scene instances placed in the zone | Container script (lifecycle hooks for NPCs as that system grows) |
| `Items` | Chests, pickups, key items | Container script (spawn/despawn, flag-driven visibility) |
| `Triggers` | `Area3D` volumes — zone exits, cutscene zones, scripted events | Container script |
| `Puzzles` | Puzzle scene instances | Container script |
| `Exploration` | `ExplorationEnvironment`, `ExplorationBGM` | On zone enter: instantiate environment scene, play BGM |
| `Combat` | `StepCounter`, `EncounterPool`, `CombatEnvironment`, `CombatBGM` | Listen to `StepCounter.threshold_reached` → pick from `EncounterPool` → emit `CombatEvents.encounter_triggered` with composition + env + bgm |

The `Combat` container is the renamed/relocated `EncounterManager` from current code. Same children, same orchestration logic — moved into the Zone, sitting as a sibling of `Exploration`.

### Why "Exploration" earns its container despite being thin

It currently holds two children (`ExplorationEnvironment`, `ExplorationBGM`). That's lighter than `Combat` but the symmetry has cognitive value — the duology between exploration mode and combat mode reads naturally in the scene tree. Both are mode-specific assets in their own subtree.

### Why content (NPCs/Items/Triggers/Puzzles) sits at zone level, not inside `Exploration`

"Exploration" is a gamestate label, not a structural one. NPCs, items, triggers, and puzzles are zone content — they exist regardless of mode. A trigger could fire after combat ends. An item could be placed but only become collectible once a flag flips. Putting them inside `Exploration` would conflate "things in the world" with "things visible during exploration mode." Flat at zone level is more honest.

---

## Lifecycle and Transitions

### Zone Load (entering an Area, or after world map travel)

1. GameManager reads the target `Area` resource → finds `entry_zone`.
2. Fade out via `ScreenFader`.
3. Free the current zone (if any). `queue_free()` is enough — children unload recursively.
4. Instantiate the new zone, add as child of `CurrentZone` slot under GameManager.
5. Place the persistent player pawn at the zone's entry point.
6. Fade in.

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
    await screen_fader.fade_out()
    _current_combat = CombatSceneTemplate.instantiate()
    add_child(_current_combat)
    _current_combat.initialize(composition, environment, bgm)
    current_zone.process_mode = Node.PROCESS_MODE_DISABLED
    await screen_fader.fade_in()

func end_combat() -> void:
    await screen_fader.fade_out()
    _current_combat.queue_free()
    _current_combat = null
    current_zone.process_mode = Node.PROCESS_MODE_INHERIT
    if _overworld_camera != null:
        _overworld_camera.make_current()
    await screen_fader.fade_in()
```

This makes combat lifecycle symmetric with zone lifecycle — both load on demand, both free on end. The `cleanup()` method previously added to `CombatScene` becomes unnecessary; `queue_free()` recursively frees all children.

### Player Persistence Across Transitions

The overworld character pawn (`overworld_character.tscn`) lives as a child of GameManager, not inside any zone. It persists across all transitions. Zone loads place it at the appropriate entry point; combat transitions disable the zone but leave the pawn in place (it's not part of the zone tree).

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

## GameManager Scope

`GameManager` is the session-level orchestrator. Its responsibilities after this design lands:

- `ScreenFader` (transition visuals)
- `CombatSceneTemplate` constant + `_current_combat` instance reference
- `CurrentZone` slot (where the active zone lives)
- The persistent player pawn
- High-level state machine: `MAINMENU` / `OVERWORLD` / `COMBAT`
- Handlers for cross-system events: `encounter_triggered`, `zone_exit_requested`, combat end

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
- `ZoneExit` scene — `Area3D` with target zone export, fires `ExplorationEvents.zone_exit_requested`.
- `ExplorationEvents.zone_exit_requested(target_zone, spawn_point)` signal.
- Spawn point convention — named `Marker3D` nodes in zone scenes, looked up by `StringName` when placing the player on zone load.
- Zone loading code in GameManager.

**Implementation order is plan territory, not spec.** A separate implementation plan will sequence the migration so each step is testable in Godot before moving on.
