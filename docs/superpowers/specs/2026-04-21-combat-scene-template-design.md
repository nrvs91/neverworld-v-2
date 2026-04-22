# Combat Scene Template — Design Spec
**Date:** 2026-04-21
**Status:** AGREED — ready for implementation plan
**Scope:** The authored spatial foundation of combat — slot positions, camera, static framing anchors, and two concrete improvements to the existing combat architecture. Does not cover combat visuals, HUD, or the combat loop.

---

## What This Is

The combat scene already exists and already works (see the end-to-end log from 2026-04-21). What it lacks is:

1. **Authored slot positions** — PlayerSpawner and EnemySpawner have slots, but they're all at the origin. We need to place them in 3D space to match the intended layout.
2. **A camera** — CombatScene has no Camera3D. Godot keeps rendering through the overworld camera when combat starts.
3. **Static framing anchors** — three authored Node3D positions (player-side, center, enemy-side) for the future camera controller to target.
4. **Ephemeral player spawning** — currently PlayerSpawner holds permanent CombatCharacter children. Both spawners should work identically: spawn on encounter start, free on encounter end.
5. **CombatCharacter simplification** — the existing visuals spec described VFXAnchor, CombatTextAnchor, and get_anchor(). These are not needed. The character root sits at its slot and never moves, so global_position IS the anchor for everything.

---

## Architecture — What Doesn't Change

The existing architecture is correct and stays:

```
GameManager (autoload, main scene)
  ├── ScreenFader
  ├── CombatScene  ← permanent disabled child, always in tree
  └── CurrentScene
        └── [forest.tscn — overworld only, no combat child]
```

- `CombatScene` remains a permanent disabled child of `GameManager`
- `encounter_triggered(composition, environment, bgm)` signal — unchanged
- `EncounterManager` structure — unchanged, CombatBGM + CombatEnvironment stay as its children
- `CombatScene.initialize(composition, environment, bgm)` — same signature

---

## Camera

### The Problem

When `CombatScene` is enabled at combat start, Godot keeps rendering through the overworld `Camera3D` unless explicitly told otherwise.

### The Fix

Add a `Camera3D` to `CombatScene.tscn`. When `initialize()` is called, the first thing it does is `$Camera3D.make_current()`. When `end_combat()` is called from GameManager, the overworld camera reclaims rendering — GameManager calls `make_current()` on the overworld's camera (or Godot picks the next available camera automatically when the scene re-enables).

### Settings

- **Projection**: Orthographic (matches overworld)
- **Size**: 3.0 (matches overworld SubViewport camera)
- **Rotation and position**: authored in the editor to frame all 9 slots with comfortable padding

### Spatial Isolation

The combat scene sits inside GameManager's scene tree, which is far from the overworld geometry. The combat camera points at the authored slot positions. Since only one camera renders at a time and the combat camera's frustum aims at the combat arena, there is no visual bleed from the overworld.

---

## Slot Layout

### Intent (from mockup)

- **Players** occupy the **lower-left** of the frame, 3 slots in a loose stagger
- **Enemies** occupy the **upper-right** of the frame, 6 slots in a wider spread
- Both parties face each other along a diagonal axis
- All 9 slots are visible without camera movement

### Authoring

Slot positions are `Node3D` children of `PlayerSpawner` and `EnemySpawner`, authored in the Godot editor. Exact coordinates are tuned visually — the spec defines intent, not numbers.

---

## CameraTargets

A `Node` named `CameraTargets` with three `Node3D` children, authored in the editor:

- `PlayerSide` — near the player cluster, for establishing shots
- `Center` — mid-battlefield, shows both parties
- `EnemySide` — near the enemy group

These are static. The future camera controller spec will animate between them. They cost nothing now.

---

## Both Spawners Are Ephemeral

**Old model:** PlayerSpawner held permanent CombatCharacter instances as pre-placed scene children. They were reset between encounters via `reset_for_combat()`.

**New model:** Both spawners work identically.

On `initialize()`:
- PlayerSpawner reads party slots from PartyManager, instantiates a fresh `CombatCharacter` per occupied slot, calls `initialize_player()`
- EnemySpawner reads CombatConfig, instantiates a fresh `CombatCharacter` per filled slot, calls `initialize_enemy()`

On `clear()`:
- Both spawners free all CombatCharacter children from their slot nodes
- Slot nodes themselves (the authored Node3Ds) stay

**Why:** Fresh node = guaranteed fresh state. No reset logic, no risk of lingering visual or token state from a previous encounter. Same code pattern for both sides.

`reset_for_combat()` on CombatCharacter is no longer needed.

---

## CombatCharacter — No Anchor Children

The `combat-visuals` spec described `VFXAnchor`, `CombatTextAnchor`, and a `get_anchor()` method. These are not built.

**Why:** The `CombatCharacter` root sits at its slot position and never moves (`CombatVisuals` tweens its own local position during actions, not the root). Therefore `character.global_position` always equals the slot position — that is the anchor for VFX, combat text, and camera targeting. No child nodes needed, no lookup method.

```
CombatCharacter (Node3D)  ← root = anchor. global_position == slot position, always.
  ├── VitalsComponent
  ├── ActiveTokens
  ├── CombatVisuals (Node3D)
  │     └── AnimatedSprite3D
  └── CombatSFXComponent
```

---

## Placeholder Environment

For testing before any real `CombatEnvironment` scene exists: a flat `CSGBox3D` (or simple `MeshInstance3D`) placed directly in `CombatScene.tscn` as a visible floor. It confirms the camera is framing the scene correctly. Removed or replaced once real environments exist.

---

## End-to-End Verification Target

When this plan is complete, running the game and walking until an encounter triggers should produce:

- Fade to black
- Combat camera activates — battlefield visible, floor visible, slot positions correct
- PlayerSpawner skips all slots silently (PartyManager has no data yet) — expected
- EnemySpawner spawns from the test CombatConfig — at least one enemy CombatCharacter at a visible slot position
- Log output: `CombatScene initialized`, no camera errors, no null reference errors
- `end_combat()` (via F1 or debug call) fades back to overworld, overworld camera resumes

---

## Out of Scope

- Camera controller behaviour (future spec)
- CombatVisuals animation beat API (`2026-04-13-combat-visuals-design.md`)
- HUD layout (`2026-04-16-combat-hud-design.md`)
- Combat loop / FSM
- Per-area authored combat scenes beyond the test map
- PartyManager data wiring (players will be skipped silently until then)
