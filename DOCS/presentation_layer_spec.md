# Presentation Layer Spec — NEVERWORLD V2

## What This Is

Every action in combat — mnemonic, reaction, item — has a visual sequence: sprite animations, movement tweens, VFX, SFX. This spec defines how those sequences are authored, dispatched, and played.

Logic and presentation are fully separated. The combat pipeline resolves damage and applies tokens. The presentation layer reacts to events and plays visuals. Neither knows the other exists except through `CombatEvents`.

---

## Core Principle

Every action maps to one authored animation scene. That scene is self-contained: it receives a caster and an array of targets, plays its sequence via `await`, and signals when done. Nothing else owns the presentation.

---

## Positioning and Anchors

Two levels of positioning, two different concerns:

**Party-level:** `CombatAnchors` defines where the player party line, enemy party line, and middle ground sit in the scene. Characters are spawned relative to these anchors. This is formation layout, not per-character state.

**Per-character:** `CombatCharacter.visual.global_position` is wherever the sprite currently is — including mid-dash, mid-knockback, etc. VFX that needs to hit a character targets this position at the moment of impact. `visual.home_position` is where the character returns to after an attack animation (the return tween destination).

Animation scenes tween `source.visual.global_position` to move a character during an attack, then tween back to `source.visual.home_position`. The parent `CombatCharacter` node stays put.

---

## Components

### 1. CharacterVisualComponent

Lives on every `CombatCharacter`. Owns the `AnimatedSprite3D` and the character's `SpriteFrames` resource.

**Responsibilities:**
- Play named animations on demand
- Track and restore a persistent base state (idle, low HP, KO)
- React to `VitalsComponent.vitals_changed` to update base state automatically

**Base states:**
```
IDLE      → plays "idle"
LOW_HP    → plays "idle_low_hp"  (threshold: cur_hp < 25% max_hp)
KO        → plays "ko"
```

**Interface:**
```gdscript
func play(anim: String) -> void              # raw play, caller handles await
func play_and_wait(anim: String) -> void     # plays anim, awaits sprite.animation_finished internally
func play_hurt() -> void                     # plays "hurt", auto-restores base when done
func set_base(state: Base) -> void           # manually override base state
```

`play_and_wait()` is the primary interface for animation scenes. It wraps `play()` + `await sprite.animation_finished` so the await contract is owned by the component, not scattered across every mnemonic scene. Animation scenes should prefer `await source.visual.play_and_wait("wind_up")` over raw `play()` + manual await.

`play_hurt()` is fire-and-forget from the skill sequence's perspective — it plays and restores base state internally. Concurrent with caster's recover tween.

**Vitals wiring** (in `_ready()`):
```gdscript
vitals.vitals_changed.connect(_on_vitals_changed)
```

---

### 2. ActionAnimator

A single `Node` in `CombatScene`. Subscribes to `CombatEvents.action_executed`. Dispatches the right animation scene by convention.

**Responsibilities:**
- Listen for `action_executed`
- Resolve animation scene path from `mnemonic_name`
- Instantiate, inject, play
- Emit `CombatEvents.action_animation_complete` when done

**Convention path:**
```gdscript
"res://resources/mnemonics/%s/%s_anim.tscn" % [id, id]
```
Where `id = mnemonic_name.to_lower()`.

**Fallback:** If no scene exists at that path, log a warning and emit `action_animation_complete` immediately. Development continues unblocked.

**Sketch:**
```gdscript
func _on_action_executed(source, targets, damage):
    var id := context.mnemonic.mnemonic_name.to_lower()
    var path := "res://resources/mnemonics/%s/%s_anim.tscn" % [id, id]
    if not ResourceLoader.exists(path):
        Log.warn("ActionAnimator — no scene for", id)
        CombatEvents.action_animation_complete.emit()
        return
    var scene := load(path).instantiate()
    add_child(scene)
    scene.execute(source, targets)
    await scene.animation_finished
    CombatEvents.action_animation_complete.emit()
```

---

### 3. ActionPipeline — Awaiting Animation

`ActionPipeline` currently has two placeholder `create_timer` sleeps. Both are replaced by awaiting `action_animation_complete` after `SkillExecutor.execute()`:

```gdscript
SkillExecutor.execute(context)
CombatEvents.action_executed.emit(context.source, context.targets, context.total_damage)
await CombatEvents.action_animation_complete   # replaces the 0.4s timer
```

The pre-action 0.5s timer (after `action_announced`) stays for now — that's the announcer beat, not a presentation concern.

---

### 4. Skill Animation Scene

One scene per mnemonic. Lives alongside its `.tres` resource:

```
resources/mnemonics/
  uskrav/
    uskrav.tres
    uskrav_anim.tscn     ← this
  viper_strike/
    viper_strike.tres
    viper_strike_anim.tscn
```

**Scene structure:**
```
UskravAnim (Node3D)
├── HitVFX (CPUParticles3D)      ← positioned at target anchor at runtime
├── HitSFX (AnimationPlayer)     ← method call tracks only, drives audio
└── (script)
```

No `AnimatedSprite3D` here — the script calls `play()` directly on the injected `CombatCharacter.visual` nodes. The characters own their sprites.

**Script interface:**
```gdscript
signal animation_finished

func execute(source: CombatCharacter, targets: Array[CombatCharacter]) -> void
```

**Sequence example (Uskrav — melee + hit VFX):**
```gdscript
func execute(source, targets):
    await source.visual.play_and_wait("wind_up")

    source.visual.play("dash")
    var t = create_tween()
    t.tween_property(source.visual, "global_position", targets[0].visual.global_position, 0.2)
    await t.finished

    await source.visual.play_and_wait("attack")

    for target in targets:
        hit_vfx.global_position = target.visual.global_position
        hit_vfx.emitting = true
        target.visual.play_hurt()

    sfx_player.play("impact")
    await get_tree().create_timer(hit_vfx.lifetime).timeout
    hit_vfx.emitting = false

    source.visual.play("recover")
    var t2 = create_tween()
    t2.tween_property(source.visual, "global_position", source.visual.home_position, 0.2)
    await t2.finished

    animation_finished.emit()
    queue_free()
```

**Rules:**
- Always emit `animation_finished` and `queue_free()` at the end
- SFX and VFX timing driven by `AnimationPlayer` method call tracks — never hardcoded audio/timing calls in sequence scripts. `AnimationPlayer` is the right tool for complex timed sequences (e.g., accelerating projectile succession: fire one, then two, then three-four-five with decreasing intervals). Key the method calls on the timeline, let the animator author the rhythm.
- VFX scenes have their own internal `AnimationPlayer` for anything more complex than `emitting`
- AoE: loop over `targets` for VFX spawn and `play_hurt()`

---

### 5. CombatEvents additions

One new signal:

```gdscript
signal action_animation_complete    # fired by ActionAnimator when scene finishes
```

`ActionAnimator` subscribes directly to the existing `action_executed` signal — no intermediate "animation requested" signal needed. `action_executed` stays clean as a pure logic signal; `ActionAnimator` is just another subscriber that happens to play visuals.

`action_executed` signature already updated to carry `targets: Array[CombatCharacter]`.

---

## Folder Structure

```
resources/
  mnemonics/
    uskrav/
      uskrav.tres
      uskrav_anim.tscn
    viper_strike/
      viper_strike.tres
      viper_strike_anim.tscn
    ...
scenes/
  combat/
    components/
      action_animator.tscn     ← ActionAnimator node
      combat_character.tscn    ← gains CharacterVisualComponent child
scripts/
  combat/
    ActionAnimator.gd
    CharacterVisualComponent.gd
```

---

## What Is Not In Scope

- Camera movement/pan — separate node, separate concern, later
- Damage number floaters — driven by existing `combat_text_shown` signal, already wired
- DoT tick visuals — `vitals_changed` + `combat_text_shown` cover it, no new plumbing needed
- Enemy basic attack animation — same pipeline, just no animation scene file yet (fallback handles it)
