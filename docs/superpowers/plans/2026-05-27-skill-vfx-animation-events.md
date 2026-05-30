# Skill VFX / SFX — Animation-Event-Driven Architecture

*2026-05-27 (rewritten 2026-05-30)*

---

## Preamble

Previous attempts collapsed a skill's visual sequence into a single type enum or a fixed
4-beat lifecycle. Both failed for the same reason: they confused **structure** with
**content**. A melee strike and a self-buff are not the same shape.

The correct model: the **AnimationPlayer owns the timeline.** It calls functions on a
`SkillPresenter` at whatever frames make sense for that animation. The presenter exposes
a vocabulary of small, specific functions — *what to do* — and the animator decides
*when* to call them by placing keyframe markers. No hardcoded beat structure. No temporal
coupling between method names and animation phases.

When real sprite art arrives, method call tracks on the AnimationPlayer will sit right
alongside sprite property tracks on the same timeline. The code doesn't change — you just
add more keyframes in the editor.

---

## Baseline (verified 2026-05-30)

Before any implementation:

- `CombatCharacter.gd` already has `@onready var visuals: CombatVisuals` and
  `@onready var sfx: CombatSFXComponent` — no changes needed to expose these.
- `ActionPipeline.gd` currently does:
  `await attacker.visuals.approach()` → `SkillExecutor.execute()` → `await attacker.visuals.recover()`
  This is the block being replaced.
- `CombatEvents.action_executed` signal exists but **is never emitted**. Damage numbers
  are currently broken as a result. This plan adds the missing emit.
- No `SkillPresentationData`, `SkillPresenter`, `AnimationPlayer` on `CombatCharacter`,
  or VFX directory exist yet. Clean slate.

---

## Architecture Overview

```
CombatCharacter (Node3D)
 ├── AnimationPlayer                    ← the timeline
 │     attack_skeleton animation:
 │       [frame N]  method call → presenter.start_approach()
 │       [frame N]  method call → presenter.spawn_self_vfx()
 │       [frame N]  method call → presenter.play_cast_sfx()
 │       [frame N]  method call → presenter.spawn_target_vfx()
 │       [frame N]  method call → presenter.play_impact_sfx()
 │       [frame N]  method call → presenter.trigger_damage()
 │       [frame N]  method call → presenter.start_recover()
 │       (end) ──→ animation_finished signal
 │
 ├── SkillPresenter (Node)             ← the vocabulary
 │     Exposes specific callable functions. The AnimationPlayer decides when
 │     to call them by where keyframes are placed. Does not know about damage.
 │
 ├── CombatVisuals (Node3D)            ← already exists
 │     approach(target_pos) and recover() — code-driven tweens.
 │
 ├── CombatSFXComponent (Node)         ← already exists
 │     Plays one-shot audio streams on demand.
 │
 └── VitalsComponent / StatsComponent / ActiveTokens / AIBehaviorComponent
       (unchanged)
```

### SkillPresenter Vocabulary

| Function | What it does |
|----------|-------------|
| `spawn_self_vfx()` | Instantiates `data.on_self_vfx` at caster's `global_position`, adds to `_vfx_container`. No-op if null. |
| `spawn_target_vfx()` | Instantiates `data.on_target_vfx` at `_target_pos`, adds to `_vfx_container`. No-op if null. |
| `play_cast_sfx()` | Plays `data.cast_sfx` via sfx component. No-op if null. |
| `play_impact_sfx()` | Plays `data.impact_sfx` via sfx component. No-op if null. |
| `start_approach()` | Calls `_visuals.approach(_target_pos)`. Starts tween — does not await. |
| `start_recover()` | Calls `_visuals.recover()`. Starts tween — does not await. |
| `trigger_damage()` | Emits `impact_triggered` signal. ActionPipeline handles the rest. |

The AnimationPlayer calls whichever subset makes sense for the skill. A self-buff might
only call `spawn_self_vfx()`, `play_cast_sfx()`, and `trigger_damage()`. A melee strike
calls `start_approach()`, then later `spawn_target_vfx()` + `play_impact_sfx()` +
`trigger_damage()`, then `start_recover()`. Same presenter, different keyframe layout.

### configure()

Before playing the animation, ActionPipeline calls:

```gdscript
presenter.configure(data, context, target_pos, vfx_container)
```

This stores all four values so the vocabulary functions can read them when called.
`data` may be null — all functions no-op cleanly if their relevant field is null.

### Approach Tween Timing

`start_approach()` starts a tween. The frame at which `trigger_damage()` fires must come
*after* the character has visually arrived. When tuning the animation, leave a small
buffer between `start_approach()` and `trigger_damage()` to account for tween easing.
**Add a comment in both `CombatVisuals.gd` and the AnimationPlayer: "approach tween
duration and keyframe gap must match — change one, change both."**

### Execution Coupling

```
presenter.trigger_damage()
  └── emits impact_triggered
        └── ActionPipeline._on_impact()
              ├── SkillExecutor.execute(_context)        ← mutates _context.total_damage
              └── CombatEvents.action_executed.emit(     ← MISSING emit — added here
                      _context.source,
                      _context.target,
                      _context.total_damage
                  )
                    └── CombatUIFSM                      ← unchanged, already listening
```

### VFX Scenes (Fire-and-Forget)

VFX scenes are fully editor-authored `.tscn` files — no shared script. A typical effect
is a `CPUParticles3D` root with `one_shot = true` and its `finished` signal wired to
`queue_free()` in the editor. No code required.

`_vfx_container` is a `Node3D` directly under `CombatScene`. VFX instances land there
and stay pinned to their spawn position even while the character is tweening. ActionPipeline
holds it as an `@export var` wired in the inspector — no relative path magic.

### Scope

**This plan covers the melee skeleton only.** Ranged spells need a travel phase
(cast → launch → travel → impact) that requires its own skeleton and its own design.
Do not shoehorn a Fireball into this.

---

## Data Flow Diagram

```
MnemonicResource (.tres)
  └── presentation: SkillPresentationData (.tres)   ← null = silent, no VFX
        ├── on_self_vfx:   PackedScene              ← editor-authored .tscn, no script
        ├── on_target_vfx: PackedScene
        ├── cast_sfx:      AudioStream
        └── impact_sfx:    AudioStream

ActionPipeline.run(mnemonic, attacker, target, actors)
  │
  ├── presenter.configure(data, context, target_pos, vfx_container)
  ├── presenter.impact_triggered.connect(_on_impact)
  ├── anim_player.play("attack_skeleton")
  │
  │   AnimationPlayer fires method calls on SkillPresenter at authored frames:
  │     start_approach()     → visuals.approach(target_pos) — non-blocking tween
  │     spawn_self_vfx()     → instantiate + add to vfx_container
  │     play_cast_sfx()      → sfx.play(cast_sfx)
  │     spawn_target_vfx()   → instantiate + add to vfx_container
  │     play_impact_sfx()    → sfx.play(impact_sfx)
  │     trigger_damage()     → emit impact_triggered
  │                               → ActionPipeline._on_impact()
  │                                   → SkillExecutor.execute(context)
  │                                   → CombatEvents.action_executed.emit(...)
  │                                       → CombatUIFSM (unchanged)
  │     start_recover()      → visuals.recover() — non-blocking tween
  │
  ├── await anim_player.animation_finished
  ├── presenter.impact_triggered.disconnect(_on_impact)
  ├── post-token pass, action_resolved, pipeline_complete
  └── (unchanged)
```

---

## File Map

### Create

| File | Purpose |
|------|---------|
| `scripts/combat/SkillPresentationData.gd` | Resource: four @export fields, all null by default |
| `scripts/combat/SkillPresenter.gd` | Vocabulary node: configure() + 7 callable functions + impact_triggered signal |
| `scenes/combat/components/skill_presenter.tscn` | Node + SkillPresenter script |
| `scenes/combat/vfx/vfx_hit_spark.tscn` | First VFX — CPUParticles3D, one_shot=true, finished→queue_free, no script |

### Modify

| File | Change |
|------|--------|
| `scripts/combat/skills/MnemonicResource.gd` | Add `@export var presentation: SkillPresentationData = null` |
| `scenes/combat/combat_character.tscn` | Add AnimationPlayer node + SkillPresenter node (instanced from skill_presenter.tscn) |
| `scripts/combat/CombatCharacter.gd` | Add `@onready var presenter: SkillPresenter` and `@onready var anim_player: AnimationPlayer` |
| `scenes/combat/combat_scene.tscn` | Add VFXContainer (Node3D) as direct child |
| `scripts/combat/ActionPipeline.gd` | Add `@export var vfx_container: Node3D` (wire in inspector). Replace approach/execute/recover block with configure + connect + play + await + disconnect. Add `_on_impact()` with the missing `CombatEvents.action_executed` emit. |

---

## Task Breakdown

### Task 1: SkillPresentationData + MnemonicResource

- Create `SkillPresentationData.gd`:

```gdscript
class_name SkillPresentationData
extends Resource

@export var on_self_vfx: PackedScene = null
@export var on_target_vfx: PackedScene = null
@export var cast_sfx: AudioStream = null
@export var impact_sfx: AudioStream = null
```

- Add to `MnemonicResource.gd`:

```gdscript
@export var presentation: SkillPresentationData = null
```

### Task 2: SkillPresenter

- Create `SkillPresenter.gd`:

```gdscript
class_name SkillPresenter
extends Node

signal impact_triggered

@export var visuals: CombatVisuals
@export var sfx: CombatSFXComponent

var _data: SkillPresentationData
var _target_pos: Vector3
var _vfx_container: Node3D

func configure(data: SkillPresentationData, target_pos: Vector3, vfx_container: Node3D) -> void:
    _data = data
    _target_pos = target_pos
    _vfx_container = vfx_container

func spawn_self_vfx() -> void:
    if _data == null or _data.on_self_vfx == null:
        return
    var vfx = _data.on_self_vfx.instantiate()
    vfx.global_position = global_position
    _vfx_container.add_child(vfx)

func spawn_target_vfx() -> void:
    if _data == null or _data.on_target_vfx == null:
        return
    var vfx = _data.on_target_vfx.instantiate()
    vfx.global_position = _target_pos
    _vfx_container.add_child(vfx)

func play_cast_sfx() -> void:
    if _data == null or _data.cast_sfx == null:
        return
    sfx.play_stream(_data.cast_sfx)

func play_impact_sfx() -> void:
    if _data == null or _data.impact_sfx == null:
        return
    sfx.play_stream(_data.impact_sfx)

func start_approach() -> void:
    # trigger_damage() keyframe must come after the approach tween visually completes
    visuals.approach(_target_pos)

func start_recover() -> void:
    visuals.recover()

func trigger_damage() -> void:
    impact_triggered.emit()
```

- Create `skill_presenter.tscn` — Node root + SkillPresenter script.
- Add AnimationPlayer node and SkillPresenter node to `combat_character.tscn`.
  Wire `SkillPresenter.visuals` and `SkillPresenter.sfx` exports in the inspector.
- Add to `CombatCharacter.gd`:

```gdscript
@onready var presenter: SkillPresenter = $SkillPresenter
@onready var anim_player: AnimationPlayer = $AnimationPlayer
```

- Create `attack_skeleton` animation in the AnimationPlayer with method call tracks
  targeting the SkillPresenter functions. For the MVP (no art), a minimal skeleton:
  - Early: `start_approach()`
  - After approach visually completes: `spawn_target_vfx()`, `play_impact_sfx()`, `trigger_damage()`
  - Shortly after: `start_recover()`
  Frame positions are tuned by feel in the editor — no hardcoded counts.
  **This is the shared animation all characters use.** See "Shared Animation" section.

### Task 3: VFX scene + VFXContainer

- Create `scenes/combat/vfx/` directory.
- Create `vfx_hit_spark.tscn` — `CPUParticles3D` root, authored in editor:
  - `one_shot = true`, `emitting = true`
  - Connect `finished` → `queue_free()` in the editor signal panel
  - No script
- Add `VFXContainer` (Node3D) as a direct child of `CombatScene` in `combat_scene.tscn`.

### Task 4: ActionPipeline refactor

Replace lines 41-47 (the approach/execute/recover block) with:

```gdscript
var target_pos: Vector3 = target.get_parent().global_position
attacker.presenter.configure(mnemonic.presentation, target_pos, vfx_container)
attacker.presenter.impact_triggered.connect(_on_impact.bind(context))
attacker.anim_player.play("attack_skeleton")
await attacker.anim_player.animation_finished
attacker.presenter.impact_triggered.disconnect(_on_impact)
```

Add `_on_impact()` and the `@export`:

```gdscript
@export var vfx_container: Node3D  # wire to VFXContainer in inspector

func _on_impact(context: ActionContext) -> void:
    SkillExecutor.execute(context)
    CombatEvents.action_executed.emit(context.source, context.target, context.total_damage)
```

Wire `ActionPipeline.vfx_container` to the `VFXContainer` node in the inspector.

### Task 5: Test data + in-game verify

- Create `resources/vfx/uskrav_presentation.tres` — SkillPresentationData with
  `on_target_vfx = vfx_hit_spark.tscn` and `impact_sfx = <any .wav>`.
- Assign it to `uskrav_tergo_lupi.tres` presentation field.
- Run combat scene. Verify:
  - Attack skeleton plays (character approaches, impact frame fires, character recovers)
  - Hit spark spawns at target position at impact frame
  - Damage numbers appear at the same frame (CombatEvents.action_executed now fires)
  - Damage numbers were broken before — this is the fix.

---

## Shared Animation Strategy

A single `attack_skeleton` animation is authored once and shared across all characters.
This is the default and the goal — it means every new character gets presentation for
free without any hand-tuning.

**How sharing works:**
All characters' AnimationPlayers reference the same `AnimationLibrary` resource
(`.tres`). The library contains `attack_skeleton`. When the animation plays on any
character, it fires the same method call keyframes at the same relative positions.
The SkillPresenter on each character receives the calls and does its job.

**When art arrives:**
Keep the method call keyframe positions fixed. Add sprite property tracks per-character
on top of the same skeleton — the warrior gets their sprite frames, the rogue gets
theirs, but `trigger_damage()` fires at the same beat for both. Different visuals,
shared rhythm. This requires authoring all character attack sprites to land their hit
at the same relative point in the animation — a deliberate content decision, not a
technical constraint.

**When a character genuinely needs different timing** (a slow heavy attacker, a
different skeleton entirely): that character gets their own AnimationLibrary and their
own authored animation. The vocabulary (function names) stays the same — only the
keyframe positions differ. This is the exception, not the default.

---

## What Stays Separate

| Concern | Owner | Status |
|---------|-------|--------|
| Character sprite frames | AnimationPlayer property tracks | Not yet — added when art exists |
| Character position tween | `CombatVisuals` | Unchanged — called by presenter |
| Character foley (grunt, hurt, KO) | `CombatSFXComponent` | Unchanged |
| UI sounds | `UISoundComponent` | Unchanged |
| Token execution | `SkillExecutor` | Unchanged — called by ActionPipeline._on_impact() |
| Turn logic | `CombatFSM` | Unchanged |
| Damage numbers | `CombatUIFSM` | Unchanged — listens to CombatEvents.action_executed |

### Future: Sprite Frame Animation

When sprite sheets arrive, open the AnimationPlayer and add property tracks targeting
`CombatVisuals/AnimatedSprite3D:animation`. Set the animation name string at each beat
frame: "windup", "dash", "strike", "recover", "idle". The method call tracks are
untouched — you're just painting frames onto an existing skeleton.

---

## The Nuke Guarantee

To remove the entire presentation layer with zero side effects, delete:
- `SkillPresentationData.gd`, `SkillPresenter.gd`, `skill_presenter.tscn`
- `scenes/combat/vfx/` and all its contents

Remove from existing files:
- `@export var presentation` from `MnemonicResource.gd`
- `AnimationPlayer` and `SkillPresenter` nodes from `combat_character.tscn`
- `@onready var presenter` and `@onready var anim_player` from `CombatCharacter.gd`
- `VFXContainer` from `combat_scene.tscn`
- Revert `ActionPipeline.gd` to the original approach/execute/recover block

Unchanged by a nuke: `CombatFSM`, all token scripts, all UI scripts, all FSM scripts,
`TurnTracker`, `CombatAnchors`, `CombatEvents`.
