# Skill VFX / SFX — Animation-Event-Driven Architecture

*2026-05-27*

---

## Preamble

The previous plan (`2026-05-26-skill-vfx-sfx.md`) attempted to model skill effects as a
single `VFXType` enum (`AURA / PROJECTILE / BURST`). Spells aren't one thing — they're
a **sequence of visual beats.** Collapsing cast, travel, and impact into one enum produced
nonsensical results (projectile spawning behind a character who'd already dashed to the
enemy's face). That plan has been rolled back in its entirety.

The correct model is common to virtually every turn-based JRPG: a character has a fixed
attack skeleton (`wind-up → dash → strike → recover`), and individual skills decorate
that skeleton with **timed VFX/SFX events** at specific beats. The timing is the
character's domain; the decorations are per-mnemonic data.

This specification replaces the single-VFXType-per-skill approach with an
AnimationPlayer-driven event system. The AnimationPlayer owns the **one true timeline.**
Everything else — character movement, VFX particles, sound effects, damage resolution —
responds to method calls emitted by that timeline.

---

## Architecture Overview

### The Central Idea

Godot's AnimationPlayer has **method call tracks.** At any frame in an animation, the
AnimationPlayer can invoke a named method on any node it can reach. This is Godot's
equivalent of Unity Animation Events or Unreal Anim Notifies — and it's the bridge
between visual timing (keyframes) and gameplay events (code).

A `CombatCharacter` contains:

```
CombatCharacter (Node3D)
 ├── AnimationPlayer                    ← the timeline
 │     attack_skeleton animation:
 │       [frame 0]   method track → presenter.on_windup()
 │       [frame 15]  method track → presenter.on_dash()
 │       [frame 30]  method track → presenter.on_impact()
 │       [frame 45]  method track → presenter.on_recover()
 │       [frame 60]  (end → animation_finished signal)
 │
 ├── SkillPresenter (Node)             ← the glue
 │     Receives method calls from the AnimationPlayer.
 │     Delegates to visuals, SFX, and VFX. Emits impact_triggered signal.
 │     Does not call SkillExecutor — does not know about damage resolution.
 │
 ├── CombatVisuals (Node3D)            ← the body
 │     AnimatedSprite3D for sprite frames.
 │     approach(target_pos) — code-driven tween toward target (cannot be keyframe;
 │       destination is runtime-dependent).
 │     recover() — tween back to home position.
 │     Sprite frame hooks for future use (attack_to_strike_hold, etc.).
 │
 ├── CombatSFXComponent (Node)         ← the voice
 │     Plays one-shot audio streams for cast/impact SFX.
 │     Does not know about timing, just receives play() calls.
 │
 └── VitalsComponent / StatsComponent / ActiveTokens
       (unchanged — these are gameplay state, not presentation)
```

### The Sequence in Detail

When the player selects a skill and confirms a target:

1. **CombatFSM** enters `ACTION_EXECUTION`, calls `ActionPipeline.run()`.
2. **ActionPipeline** extracts `SkillPresentationData` from the mnemonic.
3. **ActionPipeline** calls `presenter.configure(data, context, target_slot_pos, vfx_container)`.
4. **ActionPipeline** calls `animation_player.play("attack_skeleton")`.
5. **ActionPipeline** `await`s `animation_player.animation_finished`.
6. The **AnimationPlayer** begins playing, firing method calls on `presenter`:

| Frame | Method | What Happens |
|-------|--------|--------------|
| 0 | `on_windup()` | Spawn `on_self_vfx` at character position. Play `cast_sfx`. |
| 15 | `on_dash()` | `CombatVisuals.approach(target_slot_pos)` — slides 70% toward target. |
| 30 | `on_impact()` | Spawn `on_target_vfx` at target position. Play `impact_sfx`. Emit `impact_triggered` signal. |
| 45 | `on_recover()` | `CombatVisuals.recover()` — slides back to home. |

7. When the AnimationPlayer reaches the end (frame 60), `animation_finished` fires.
8. **ActionPipeline** resumes, does post-token pass, emits `pipeline_complete`.

`ActionPipeline` connects to `presenter.impact_triggered` before playing the animation.
When `impact_triggered` fires at frame 30, ActionPipeline calls `SkillExecutor.execute()`
then emits `action_executed` on `CombatEvents`. Note: `action_executed` is not currently
emitted anywhere in the pipeline — this is a missing emit, not a moved one. Adding it
here is what actually makes CombatUIFSM's damage numbers work. No change to CombatUIFSM.
ActionPipeline disconnects its `_on_impact` handler after `animation_finished` resolves.
The presenter itself has no knowledge of damage.

The AnimationPlayer can be scrubbed, looped, and previewed in the editor. Method call
tracks appear as labeled markers on the timeline. You can see exactly when `on_impact()`
fires relative to when `on_dash()` starts — and nudge keyframes with the mouse.

### Why approach/recover Stay as Code Tweens

The target position is **runtime-dependent:** the player might target ZOMBIE_A at
slot 3 or ZOMBIE_B at slot 2. A static keyframe in the AnimationPlayer can't know
the destination ahead of time. The approach code tween calculates the direction and
distance dynamically.

The AnimationPlayer still owns *when* the dash begins and ends. It calls
`presenter.on_dash()` which calls `visuals.approach(dynamic_target_pos)`. The tween
runs independently in the background — by the time `on_impact()` fires (15 frames
later), the character should have already arrived. The keyframe spacing is tuned to
match the tween's duration.

In the future, if every character's approach takes the same fixed duration, the
approach tween could become a position keyframe track on the AnimationPlayer with
the start position set dynamically before playing. For now, the code tween is simpler
and already works.

### How SkillPresentationData Decorates the Skeleton

Every mnemonic gets a `@export var presentation: SkillPresentationData`. If it's
`null`, the attack skeleton plays with no extras — no VFX, no SFX. Damage still
resolves at `on_impact()`. This is the default: a silent, visual-effect-free basic
attack.

`SkillPresentationData` is a Resource with four optional fields, all `null` by default:

| Field | Type | Meaning |
|-------|------|---------|
| `on_self_vfx` | `PackedScene` | Particle effect that plays at the caster's position at wind-up. Null → skip. |
| `on_target_vfx` | `PackedScene` | Particle effect that plays at the target's position at impact. Null → skip. |
| `cast_sfx` | `AudioStream` | Sound played at wind-up. Null → silent. |
| `impact_sfx` | `AudioStream` | Sound played at impact. Null → silent. |

This means:

- **Uskrav** (pure melee strike): `on_self_vfx = null`, `on_target_vfx = hit_spark.tscn`, `impact_sfx = slash.wav`. No cast VFX.
- **Viper Strike** (poison-enhanced strike): `on_self_vfx = purple_puff.tscn`, `on_target_vfx = hit_spark.tscn`, `cast_sfx = poison_hiss.wav`, `impact_sfx = slash.wav`.
- **Empower Stance** (self-buff): `on_self_vfx = aura_ring.tscn`, `on_target_vfx = null`, `cast_sfx = power_up.wav`.

Same melee skeleton. Different decorations.

> **Scope: this plan covers the melee skeleton only.** Skills that need a travel phase
> (projectile spells, ranged attacks) do not fit the 4-beat windup→dash→impact→recover
> model — a ranged spell needs cast→launch→travel→impact, which is a different beat
> structure entirely. When ranged skills are designed, they will get their own skeleton
> and their own `SkillPresentation` subclass. Don't shoehorn a Fireball into this.

### Damage Numbers

`CombatUIFSM` already listens to `action_executed` on `CombatEvents` to spawn damage
numbers — and it stays that way. No change to CombatUIFSM.

`action_executed` is not currently emitted anywhere in the pipeline (confirmed missing —
the emit was lost in a prior refactor). This plan adds it inside `_on_impact()`:

```gdscript
func _on_impact() -> void:
    SkillExecutor.execute(_context)
    CombatEvents.action_executed.emit(_context.source, _context.target, _context.total_damage)
```

`SkillExecutor.execute()` mutates `_context.total_damage`, so it's readable immediately
after. Damage numbers now appear at the exact frame impact VFX spawns.

### VFX Scenes (Fire-and-Forget)

VFX scenes are fully editor-authored `.tscn` files — no shared script. A typical effect
is a `CPUParticles3D` root with `one_shot = true` and its `finished` signal wired to
`queue_free()` in the editor. No code required.

The presenter spawns one like this:

```gdscript
var vfx = data.on_target_vfx.instantiate()
vfx.global_position = target_pos
_vfx_container.add_child(vfx)
```

`vfx_container` is a `Node3D` that lives directly under `CombatScene` — a stable parent
that doesn't move. VFX added there stay pinned to their spawn position even while the
character is tweening during approach or recover. `vfx_container` is passed into
`presenter.configure()` by ActionPipeline, which holds it as an `@export var` wired in
the inspector. Do not use a hardcoded `$"../VFXContainer"` path — relative paths break
silently if the scene tree changes.

Add a script to a specific VFX scene only if that effect genuinely needs custom logic
(e.g. a multi-stage effect with its own timeline). The default is zero script.

`SkillPresentationData` has two `PackedScene` fields (`on_self_vfx` and `on_target_vfx`)
so skills can point to different `.tscn` files with different particle configurations.
The split is in the data — the scenes themselves are independent.

---

## Data Flow Diagram

```
MnemonicResource (.tres)
  └── presentation: SkillPresentationData (.tres)
        ├── on_self_vfx: PackedScene (→ any editor-authored VFX .tscn)
        ├── on_target_vfx: PackedScene (→ any editor-authored VFX .tscn)
        ├── cast_sfx: AudioStream (.wav)
        └── impact_sfx: AudioStream (.wav)

ActionPipeline.run(mnemonic, attacker, target)
  │
  ├── presenter.configure(data, context, target_slot_pos, vfx_container)
  │       Stores data for the on_*() calls to come.
  │
  ├── presenter.impact_triggered.connect(_on_impact)
  │       _on_impact:
  │         → SkillExecutor.execute(context)
  │         → CombatEvents.emit_signal("action_executed", ...)  ← same as before
  │
  ├── animation_player.play("attack_skeleton")
  │       ┌──────────────────────────────────┐
  │       │ AnimationPlayer (editor-authored) │
  │       │                                  │
  │       │  on_windup() ──→ SkillPresenter  │──→ VFX on self, cast SFX
  │       │  on_dash()    ──→ SkillPresenter  │──→ CombatVisuals.approach()
  │       │  on_impact()  ──→ SkillPresenter  │──→ VFX on target, impact SFX,
  │       │                                  │    emit impact_triggered
  │       │                                  │      → ActionPipeline._on_impact()
  │       │                                  │          → SkillExecutor.execute()
  │       │                                  │          → CombatEvents.action_executed
  │       │                                  │              → CombatUIFSM (unchanged)
  │       │  on_recover() ──→ SkillPresenter  │──→ CombatVisuals.recover()
  │       │                                  │
  │       │  (end) ──→ animation_finished    │
  │       └──────────────────────────────────┘
  │
  ├── await animation_finished
  ├── presenter.impact_triggered.disconnect(_on_impact)
  ├── post-token pass, action_resolved, pipeline_complete
  └── (unchanged)
```

---

## File Map

### Create

| File | Purpose |
|------|---------|
| `scripts/combat/SkillPresentationData.gd` | Resource: four @export fields |
| `scripts/combat/SkillPresenter.gd` | Glue node: configure(), on_*(), impact_triggered signal |
| `scenes/combat/components/skill_presenter.tscn` | Node + SkillPresenter script |
| `scenes/combat/vfx/vfx_hit_spark.tscn` | First VFX scene — CPUParticles3D, one_shot=true, finished→queue_free. No script. |

### Modify

| File | Change |
|------|--------|
| `scripts/combat/skills/MnemonicResource.gd` | Add `@export var presentation: SkillPresentationData = null` |
| `scenes/combat/combat_character.tscn` | Add AnimationPlayer node, add SkillPresenter node |
| `scenes/combat/combat_scene.tscn` | Add VFXContainer (Node3D) as direct child |
| `scripts/combat/CombatCharacter.gd` | Add `@onready var presenter: SkillPresenter`, `@onready var anim_player: AnimationPlayer` |
| `scripts/combat/ActionPipeline.gd` | Add `@export var vfx_container: Node3D` (wire in inspector). Replace approach/execute/recover with: configure presenter (passing vfx_container), connect impact_triggered → _on_impact, play animation, await finished, disconnect. Add missing action_executed emit inside _on_impact(). |

---

## Task Breakdown

### Task 1: SkillPresentationData + MnemonicResource

- Create `SkillPresentationData.gd` — Resource with four `@export var` fields, all default null.
- Add `@export var presentation: SkillPresentationData = null` to `MnemonicResource.gd`.

### Task 2: SkillPresenter + wire into CombatCharacter

- Create `SkillPresenter.gd` — `configure(data, context, target_pos, vfx_container)`, `on_windup()`, `on_dash()`, `on_impact()`, `on_recover()`. `impact_triggered` signal. No SkillExecutor reference — presenter is presentation only. Stores `vfx_container` reference for spawning effects.
- Create `skill_presenter.tscn`.
- Add `AnimationPlayer` node and `SkillPresenter` node to `combat_character.tscn`.
- Create `attack_skeleton` animation with four method call tracks targeting `SkillPresenter`.
- Add `@onready var presenter` and `@onready var anim_player` to `CombatCharacter.gd`.
- **Timing note:** the frame gap between `on_dash()` (frame 15) and `on_impact()` (frame 30) is 15 frames = 0.25s at 60fps. The current approach tween is 0.2s — a 0.05s buffer, which is workable but tight. Leave a comment in both `CombatVisuals.gd` (at the tween duration constant) and on the AnimationPlayer keyframes: *"tween duration and keyframe gap must match — change one, change both."* Future you will thank present you.

### Task 3: VFX scene

- Create `vfx_hit_spark.tscn` — `CPUParticles3D` root node, authored entirely in the editor:
  - `one_shot = true`, `emitting = true`
  - Connect `finished` signal → `queue_free()` in the editor
  - No script
- This is the first concrete VFX effect. Future effects are additional `.tscn` files following the same pattern. A script is only added to a scene if that specific effect needs custom logic.

### Task 4: ActionPipeline refactor

- Add `@export var vfx_container: Node3D` to ActionPipeline and wire it to `VFXContainer` in the inspector. Do not use a relative path — it breaks silently on scene tree changes.
- Replace the approach→execute→recover block with:
  1. `presenter.configure(data, context, target_slot_pos, vfx_container)`
  2. `presenter.impact_triggered.connect(_on_impact)`
  3. `anim_player.play("attack_skeleton")`
  4. `await anim_player.animation_finished`
  5. `presenter.impact_triggered.disconnect(_on_impact)`
- `_on_impact()` calls `SkillExecutor.execute(context)` then emits `action_executed` on `CombatEvents` — moving the emit that was previously at the end of the pipeline to the impact frame.

### Task 5: CombatUIFSM — no change

- CombatUIFSM already listens to `CombatEvents.action_executed`. No edits required. The damage numbers will now appear at the correct frame automatically because ActionPipeline emits earlier.

### Task 6: Test data + in-game verify

- Create `resources/vfx/uskrav_presentation.tres` (SkillPresentationData with only `on_target_vfx` + `impact_sfx`).
- Assign to `uskrav_tergo_lupi.tres`.
- Run combat scene, verify attack skeleton plays, damage resolves at impact frame.

---

## What Stays Separate

| Concern | Owner | Unchanged |
|---------|-------|-----------|
| Character sprite frames | `CombatVisuals` (AnimatedSprite3D) | Yes — AnimationPlayer can drive sprite frames via property tracks when art exists |
| Character foley (grunt, hurt, KO) | `CombatSFXComponent` | Yes — separate from skill SFX |
| UI sounds (nav, confirm, cancel) | `UISoundComponent` | Yes |
| Token execution | `SkillExecutor` | Yes — called by ActionPipeline in response to `impact_triggered` signal; presenter never touches it |
| Turn logic | `CombatFSM` | Yes — no knowledge of presentation layer |
| UI menu/targeting | `CombatUIFSM` | Yes — fully unchanged. Still listens to `CombatEvents.action_executed`. |

### Future: Sprite Frame Animation

When sprite sheets with actual attack animations arrive (wind-up frames, strike
frames, recover frames), the AnimationPlayer gets additional property tracks
that set `AnimatedSprite3D.frame` or call `sprite.play("attack")` at the
appropriate keyframes. The method call tracks stay exactly where they are —
they become `call_on_self` in the AnimationPlayer track naming. No code changes.

---

## The Nuke Guarantee

The system can be deleted and restarted with zero changes to:
- `CombatFSM.gd` — unchanged
- All token scripts
- All FSM scripts
- All UI scripts
- `TurnTracker`, `CombatAnchors`, `CombatEvents` autoloads

To nuke: delete `SkillPresentationData.gd`, `SkillPresenter.gd`, `skill_presenter.tscn`,
any VFX `.tscn` files, remove the presentation field from `MnemonicResource`,
remove the AnimationPlayer and SkillPresenter from `combat_character.tscn`,
and revert `ActionPipeline` to use the old approach/execute/recover block.
No other files are touched.
