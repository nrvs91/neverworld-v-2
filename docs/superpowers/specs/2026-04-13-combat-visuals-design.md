# Combat Visuals — Design Spec
**Date:** 2026-04-13 (revised 2026-04-15)
**Status:** AGREED — ready for implementation plan
**Scope:** How combat characters are displayed, animated, and decorated with skill VFX/SFX, status tokens, and damage feedback. No combat loop mechanics.

---

## Purpose

Define the visual subsystem for combat actors — what moves, what plays animations, what spawns VFX, what plays sound, what displays status — so that Task 9 of `2026-04-08-combat-transition.md` can be replaced with a clean, composable implementation instead of a null-guarded overworld adaptation.

This spec supersedes Task 9's "make `VisualComponent.controller` optional" approach. The existing overworld `VisualComponent` stays untouched.

---

## Guiding Principles

1. **Composition over sharing.** Overworld and combat visuals have almost no common behaviour. They share `AnimatedSprite3D` as a primitive and nothing else. Forcing a shared component leaks concerns both ways.
2. **Tiny character vocabulary, rich skill identity.** Every character has a small fixed set of action animations (attack, cast, item, hurt, KO, etc.). Skill identity lives in the VFX layer, not character animation.
3. **Static layout is a design feature, not a limitation.** Fixed camera, fixed positions, fixed facings. Halves the sprite workload, removes facing/rotation logic, makes anchors trivially authored. Characters sit at their slot — only their `CombatVisuals` child tweens during an action.
4. **Particles + shaders for skill VFX — no sprite VFX, ever.** Skills are expressed through `GPUParticles3D`, shaders, and in-engine effects. No flipbook hero effects. Character sprites are the only sprite-based visuals in combat.
5. **Signal-driven consumers.** `ActiveTokens` emits; `TokenDisplay.tscn` (instanced in both player cards and enemy nameplates) subscribes. The data node doesn't know who's listening.
6. **Placeholder art, full systems.** Art can be a coloured box with a label — the *system* around it (animation slots, anchors, SFX hooks, VFX scenes, token displays) ships in full from day one. We do not defer architecture behind "vertical slice" excuses.

---

## Scope

### In scope
- `CombatVisuals` scene — sprite + base-state swap + action animation API, owned by `combat_character`
- `CombatSFXComponent` — character-level sound effects (footsteps, swing, cast, hurt, KO'd)
- Character animation vocabulary (12 slots, see table)
- Anchor nodes for VFX and damage popups — children of `combat_character` root (not `CombatVisuals`)
- `SkillVFX` resource — in-engine particle/shader scene spawned at an anchor
- `SkillSFX` resource — audio stream played on skill use
- Token visualization — see `2026-04-16-combat-hud-design.md`
- Approach/recover movement (local-position tween on `CombatVisuals`, not on the character root)
- `CombatTextComponent` — dedicated component, signal-driven, owns popup spawning and tweening
- Base state switching (`Idle` / `Low_HP` / `Guarding`)

### Out of scope
- Combat FSM (`FSMSTATE_ActionExecution`) — consumer of this API, not part of it
- Combat camera behaviour — deferred to its own spec (an integration hook is reserved here)
- Skill resource shape (references `SkillVFX` + `SkillSFX`, but skill data is a separate spec)
- `CombatCard` UI layout and styling (separate UI spec)
- `CombatText.tscn` scene internals (separate spec; API sketched here)
- `TokenDisplay` internal layout (separate spec; contract sketched here)
- Overworld `VisualComponent` — explicitly unchanged
- Ultimate / limit-break bespoke animations (backdoor API reserved via `play_custom()`)

---

## Layout Assumptions

The combat scene is statically laid out:

- **Camera** is fixed, orthographic, via the existing 640×360 SubViewport pipeline. Camera controller is deferred to its own spec; combat visuals do not steer the camera.
- **Players** occupy the lower-right of the frame, rendered **back-view** (camera sees their backs).
- **Enemies** occupy the upper-left of the frame, rendered **front-view** (camera sees their faces).
- Both parties face each other along a diagonal axis. Neither party rotates or turns during combat.
- Slot positions are authored in `PlayerSpawner.tscn` (Slot1–3) and `EnemySpawner.tscn` (Slot1–6), each slot a `Node3D`.

**Consequences:**
- Sprite sheets per character need only one facing direction (back for players, front for enemies). Half the art budget of a 4-directional system.
- No `face()` API on `CombatVisuals`. Parties do not turn.
- Approach motion is a straight tween along a known vector. No pathing, no rotation.
- Anchors at the character root sit at slot-relative offsets — stable regardless of whether `CombatVisuals` is mid-tween.

---

## Scene Shape

### `combat_character.tscn`

```
combat_character (Node3D)                   — sits at slot, NEVER moves
  ├── VitalsComponent                      — cur_hp / cur_mp / cur_ap
  ├── ActiveTokens                         — holds tokens, emits add/remove/update signals
  ├── CombatVisuals (Node3D)               — the visual subsystem; tweens its own local position during actions
  │     └── AnimatedSprite3D               — the character sprite
  ├── CombatSFXComponent                   — plays character-level audio (swing, cast, hurt, ko)
  ├── VFXAnchor (Node3D)                   — where skill VFX spawn on this character (e.g. chest height)
  └── CombatTextAnchor (Node3D)            — where floating combat text spawns (damage, heal, miss, resist, status, etc.)
```

**Why anchors live on the character root, not on `CombatVisuals`:** targets are the *slot*, not the tween-offset visual. A skill aimed at enemy slot 3 should hit slot 3 whether or not that enemy's sprite is currently mid-approach. Anchors on the root are stable positional references; `CombatVisuals` moves freely without dragging targeting geometry with it.

**Why `CombatVisuals` owns its own local position:** during approach/recover, only the visual representation moves. The `combat_character` root stays at its authored slot — that's the combatant's "home." `CombatVisuals` tweens its local position from `Vector3.ZERO` to a target offset and back.

**Player vs enemy:** both use `combat_character.tscn`. Both have `ActiveTokens`; both have their tokens drawn by `TokenDisplay.tscn` instanced in their respective HUD card. See `2026-04-16-combat-hud-design.md`.

---

## Character Animation Vocabulary

Twelve animation slots. Every combat character authors all of them (art can be placeholder; the slot must exist).

| Animation | Loop | Hold pattern | Purpose |
|---|---|---|---|
| `Idle` | yes | — | Default base state, subtle sway optional |
| `Low_HP` | yes | — | Base state when HP < threshold OR an ailment token is present |
| `Guarding` | yes | — | Base state when a defensive token is active (DEFEND, BLOCK, GUARD, etc.) |
| `Combat_Entry` | no | one-shot | Plays when combat begins — unsheathing, crack knuckles, stance. Player-only in practice. |
| `Combat_Exit` | no | one-shot | Plays when combat ends cleanly — victory pose. Replaces any separate `Victory` clip. |
| `Attack_Entry` | no | **two holds** | 6-frame structure (see below) — windup, motion hold, strike, strike hold |
| `Attack_Exit` | no | **one hold** | 6-frame structure — recoil, motion hold (covers `recover()`), settle |
| `Cast_Entry` | no | **two holds** | Same structure as `Attack_Entry`, but casting gesture instead of weapon swing |
| `Cast_Exit` | no | **one hold** | Same structure as `Attack_Exit` |
| `Item_Use` | no | one-shot | Drink/throw/apply gesture |
| `Hurt` | no | one-shot | Flinch on taking damage |
| `KO'd` | no | terminal | Fall / dissolve; final frame is the "downed" pose; actor stays on this until revived or cleared |

### The 6-frame / two-clip structure for actions

A full attack action is split across two clips (`Attack_Entry` + `Attack_Exit`), each ~6 frames, with deliberate hold frames that **cover external beats** — the tween across the battlefield and the VFX playback.

**`Attack_Entry` (6 frames):**

| Frame | Content | Role |
|---|---|---|
| 1–2 | Windup (in-place anticipation) | plays through |
| 3 | "Crossing the battlefield" pose | **HOLD** — covers the `approach()` tween |
| 4–5 | The swing in motion | plays through |
| 6 | Strike peak / impact pose | **HOLD** — covers skill VFX + damage resolution |

Frame 6 is both the end of the clip and the second hold — playback pauses there, does not advance past it until the next beat method is called.

**`Attack_Exit` (6 frames):**

Frame 1 visually continues from Entry's final frame (animator's problem, not ours).

| Frame | Content | Role |
|---|---|---|
| 1–2 | Recoil / wind-down from the hit | plays through |
| 3 | "Returning to slot" pose | **HOLD** — covers the `recover()` tween |
| 4–6 | Settle back to neutral | plays through; blends to base state after |

### Runtime beat sequence

```
play Attack_Entry → runs 1-2 → pauses on frame 3 (motion hold)
    … approach() tween runs while frame 3 holds …
resume → plays 4-5-6 → pauses on frame 6 (strike hold)
    … skill VFX plays, damage resolves, target plays Hurt …
play Attack_Exit → runs 1-2 → pauses on frame 3 (motion hold)
    … recover() tween runs while frame 3 holds …
resume → plays 4-5-6 → returns to base state
```

Same structure applies to `Cast_Entry` / `Cast_Exit` (gesture instead of swing; frame 3 hold covers approach/recover, frame 6 hold of `Cast_Entry` covers the spell's VFX).

**If an action doesn't need approach/recover** (e.g. a cast that stays in place), the controller simply doesn't call `approach()` / `recover()` between beats. The animation briefly pauses on the motion-hold frame and moves on. No special case, no branching API.

### Base state swap — `Idle` / `Low_HP` / `Guarding`

`CombatVisuals` exposes `set_base_state(state: StringName)`. When no action is playing, the component plays whichever state was last set. The `combat_character` orchestrator decides, with a clear priority:

```gdscript
# Defined in scripts/combat/TokenType.gd (or wherever token definitions live).
# An "instant" token type isn't needed — instant damage from a bread-and-butter
# attack isn't a persistent token, it resolves and doesn't enter ActiveTokens.
enum TokenType {
    DEFENSIVE,   # active guard stance (Guard action, Protect buffs)
    CC,          # crowd control — stun, freeze, petrify (action-denying ailments)
    DOT,         # damage over time — poison, bleed, burn (tick-damage ailments)
    HOT,         # heal over time (regen)
    BUFF,        # stat-up, resistances gained, accuracy-up, etc.
    DEBUFF,      # stat-down, resistances lost, accuracy-down, etc.
    MARK,        # tag used by follow-up skills (flagged, exposed, cursed targets)
}

# "Ailments" is the umbrella term covering CC and DOT — the token categories that
# visibly afflict the character. DEBUFF is a stat modifier, not an ailment, and
# does NOT alter base state.

func _update_base_state() -> void:
    var guarding: bool = tokens.has_any_of_type(TokenType.DEFENSIVE)
    var low_hp: bool = float(vitals.cur_hp) / vitals.max_hp < COMBAT_LOW_HP_THRESHOLD
    var afflicted: bool = tokens.has_any_of_type(TokenType.CC) or tokens.has_any_of_type(TokenType.DOT)

    var state: StringName
    if guarding:
        state = &"Guarding"          # active defensive stance wins
    elif low_hp or afflicted:
        state = &"Low_HP"            # passive distress — low HP or visible ailment
    else:
        state = &"Idle"

    visuals.set_base_state(state)
```

**Priority rationale:** `Guarding` is an active choice (the player/AI put this character into defence), and it should read visually even if the character is also low-HP or poisoned — the stance is what's currently expressive. `Low_HP` is the passive fallback when nothing else is active. `Idle` is the default.

**Why CC + DOT, not DEBUFF:** stun/freeze/petrify and poison/bleed/burn are *ailments* — the character is visibly suffering, so the hunched posture reads. A stat-down debuff (attack-down, accuracy-down) is a hidden modifier and doesn't warrant a sprite change. `BUFF`, `HOT`, `DEBUFF`, `MARK` never drive base state; they surface through the `TokenDisplay` pip row and VFX instead.

Called on `VitalsComponent.hp_changed`, `ActiveTokens.token_added`, `ActiveTokens.token_removed`. Never called mid-action — the new state takes effect after the current action clip returns. Also a no-op while `KO'd` is held.

### Backdoor for exceptions

`CombatVisuals.play_custom(anim_name: String)` exists for the rare bespoke case (ultimates, limit breaks, scripted moments). Not used in the baseline pipeline.

---

## `CombatVisuals` API

Thin, signal-driven, `await`-friendly. Each method is an atom; `FSMSTATE_ActionExecution` composes them.

**Anchors are not owned here.** `CombatVisuals` never looks up its own anchors. Anything spawned at an anchor (skill VFX, floating combat text, nameplates, tokens) goes through `combat_character.get_anchor(kind)` on the root. See the [Anchors](#anchors) section.

```gdscript
class_name CombatVisuals
extends Node3D

# --- Setup ---
func setup(sprite_frames: SpriteFrames) -> void
    # Assigns SpriteFrames to the AnimatedSprite3D, plays current base state (Idle by default).

# --- Base state ---
func set_base_state(state: StringName) -> void
    # "Idle", "Low_HP", or "Guarding". If no action is playing, swap immediately.
    # If an action is playing, the new base state takes effect on the next return-to-base.

# --- Movement (local position tween) ---
func approach(target_offset: Vector3, duration: float = 0.2) -> void
    # Tweens local position from ZERO to target_offset. Awaits tween completion.
    # NOTE: callers compute target_offset as (target.global_position - self_character.global_position).
    # This works because character roots have no rotation in the static layout — local == world for deltas.
    # If we ever allow rotated roots, this needs to convert to local space.

func recover(duration: float = 0.2) -> void
    # Tweens local position back to ZERO. Awaits tween completion.

# --- Attack beats (four atoms; hold frames authored on Attack_Entry/Exit) ---
func attack_to_motion_hold() -> void
    # Plays Attack_Entry frames 1-2, pauses on frame 3 ("crossing" pose).
    # Awaits the pause (returns once frame 3 is reached). Caller then runs approach() while the hold sits.

func attack_to_strike_hold() -> void
    # Resumes Attack_Entry, plays 4-6, pauses on frame 6 (strike pose held at impact).
    # Awaits the pause. Caller then runs skill VFX / damage resolution while the hold sits.

func attack_to_recover_hold() -> void
    # Plays Attack_Exit frames 1-2, pauses on frame 3 ("returning" pose).
    # Awaits the pause. Caller then runs recover() while the hold sits.

func attack_finish() -> void
    # Resumes Attack_Exit, plays 4-6. Awaits clip completion, returns to base state.

# --- Cast beats (same four-atom shape as attack) ---
# All four await their pause / completion point, same semantics as the attack beats.
func cast_to_motion_hold() -> void
func cast_to_release_hold() -> void
func cast_to_recover_hold() -> void
func cast_finish() -> void
    # Same pattern. release-hold covers the spell VFX instead of a physical strike.

# --- One-shot animations ---
func play_combat_entry() -> void
    # Plays Combat_Entry, awaits completion, returns to base state.

func play_combat_exit() -> void
    # Plays Combat_Exit (victory). Awaits completion, holds final frame.

func play_item_use() -> void
    # Plays Item_Use, awaits completion, returns to base state.

func play_hurt() -> void
    # Plays Hurt, awaits completion, returns to base state.
    # Called when damage > 0 was applied (HIT / CRIT / WEAK / RESISTED-with-damage).

func play_dodge_slide() -> void
    # Small lateral tween on CombatVisuals local position — sprite slides ~0.15 units aside and back.
    # No animation change. Used for MISS / PARRY / zero-damage outcomes where the target visually evades.
    # Awaits tween completion.

func play_ko() -> void
    # Plays KO'd, awaits completion, holds final frame. No return to base state.
    # While KO'd is held, set_base_state() is a no-op — only an explicit revive action clears KO.

# --- Escape hatch ---
func play_custom(anim_name: String) -> void
    # For bespoke animations (ultimates, scripted). Awaits completion.
```

### Implementing the mid-frame hold

`AnimatedSprite3D` has no native "play until frame N then pause." Pattern:

```gdscript
# Start a clip and pause on the target frame.
func _play_until_frame(anim: StringName, target_frame: int) -> void:
    sprite.play(anim)
    while sprite.frame < target_frame:
        await sprite.frame_changed
    sprite.pause()

# Resume the currently paused clip and pause again at a later frame.
# Used for Entry's second hold (motion → strike).
func _resume_until_frame(target_frame: int) -> void:
    sprite.play()
    while sprite.frame < target_frame:
        await sprite.frame_changed
    sprite.pause()

# Resume the currently paused clip to its end.
# Used for Exit's "finish" beat.
func _resume_to_end() -> void:
    sprite.play()
    await sprite.animation_finished
```

Each clip authors its hold frames explicitly. `Attack_Entry` / `Cast_Entry` have **two** hold frames (motion at frame 3, strike/release at frame 6). `Attack_Exit` / `Cast_Exit` have **one** hold frame (motion at frame 3). Hold-frame indices can live as an exported per-anim dictionary on `CombatVisuals` or as a convention on the `SpriteFrames` resource — decide at implementation time.

### A canonical action sequence (visuals-only view)

This is the sequence as `FSMSTATE_ActionExecution` would write it, focusing on the visual calls. The full cross-system flow (calculator, bus emits, vitals mutation, text spawner) is in [Event Flow & Orchestration](#event-flow--orchestration).

```gdscript
# SLASH: physical attack with a particle/shader impact VFX and a swing SFX
var target_offset: Vector3 = target.global_position - attacker.global_position

# --- 1. Windup + approach ---
await attacker.visuals.attack_to_motion_hold()     # Entry 1-2 play, pause on frame 3
await attacker.visuals.approach(target_offset)     # tween across while motion-held

# --- 2. Resolve BEFORE the strike so we know which target reaction to run ---
var result := CombatCalculator.resolve_attack(attacker, target, skill)

# --- 3. Strike ---
attacker.sfx.play_swing()
await attacker.visuals.attack_to_strike_hold()     # Entry 4-6, pause on frame 6 (impact)
CombatEvents.attack_resolved.emit(target, result)  # CombatTextComponent spawns text from this

# --- 4. Target reaction — see the Target reaction rule table ---
if result.damage > 0:
    target.vitals.apply_damage(result.damage)      # dumb ledger mutation; hp_changed fires
    await skill.vfx.play_on(target.get_anchor("vfx"))
    skill.sfx.play_on(target.sfx)
    await target.visuals.play_hurt()
else:
    await target.visuals.play_dodge_slide()        # MISS / PARRY / zero-damage RESISTED

# --- 5. Recoil + recover ---
await attacker.visuals.attack_to_recover_hold()    # Exit 1-2, pause on frame 3
await attacker.visuals.recover()                   # tween home while motion-held

# --- 6. Settle ---
await attacker.visuals.attack_finish()             # Exit 4-6, return to base state
```

Every beat is independently tunable by `FSMSTATE_ActionExecution`. Nothing ever calls `CombatTextComponent` directly — it listens on the bus and reacts. The full cross-system flow (bus emits, vitals mutation, KO handling) is in [Event Flow & Orchestration](#event-flow--orchestration).

---

## `CombatSFXComponent` + `CombatSFX` resource

Character-level audio (not per-skill) lives in its own component — not on `CharacterData`, not on `CombatVisuals`. Composition: visuals do visuals, SFX does SFX.

```gdscript
class_name CombatSFX
extends Resource

@export var swing: AudioStream
@export var cast: AudioStream
@export var hurt: AudioStream
@export var ko: AudioStream
@export var footstep: AudioStream   # optional, for approach
@export var pitch_variance: float = 0.05
```

```gdscript
class_name CombatSFXComponent
extends Node

@export var sfx: CombatSFX

func play_swing() -> void
func play_cast() -> void
func play_hurt() -> void
func play_ko() -> void
func play_footstep() -> void
```

Each method picks the right stream, applies a small random pitch shift, and plays it on an internal `AudioStreamPlayer3D` positioned at the character. Non-blocking.

**Overlap is accepted.** A single `AudioStreamPlayer3D` only plays one stream at a time — a new `play()` interrupts the current one. In practice combat sounds fire close enough in sequence that clipping is rare and tolerable. If it ever becomes a real problem, swap in a small pool of players and round-robin; no API change required.

Assigned in the combat character's scene; `CharacterData` stays data-only.

---

## Skill VFX & SFX (split)

Per-skill audiovisual assets live in two sibling resources on the skill:

### `SkillVFX.gd`
```gdscript
class_name SkillVFX
extends Resource

@export var scene: PackedScene        # scene root containing GPUParticles3D / shader quads / etc.
@export var duration_hint: float = 0.0  # fallback for cases where self-free timing isn't enough

func play_on(anchor: Node3D) -> void:
    var instance: Node3D = scene.instantiate()
    anchor.add_child(instance)
    await instance.tree_exited
```

### `SkillSFX.gd`
```gdscript
class_name SkillSFX
extends Resource

@export var stream: AudioStream
@export var pitch_variance: float = 0.0
@export var volume_db: float = 0.0

func play_on(sfx_component: CombatSFXComponent) -> void
    # Plays the stream on the target's AudioStreamPlayer3D with variance applied. Non-blocking.
```

**Why split VFX and SFX:** visuals and audio are independently authorable, independently tunable, independently swappable. A skill can reskin its SFX for a variant without touching the VFX scene, and vice versa. This also mirrors the character-side split (`CombatVisuals` vs `CombatSFXComponent`).

### `SkillVFX.tscn` shape (per-skill asset)

```
SkillVFX (Node3D, script attached)
  └── GPUParticles3D (+ shader materials / mesh instances as needed)
      # On ready: emit once. On finished: queue_free() the root.
```

**No sprite-based skill VFX.** The skill visual layer is particles + shaders + meshes. Character sprites are the only sprite-based visuals in combat.

---

## Anchors

Anchors are authored `Node3D` children of `combat_character` root at offsets that make sense for the character:

| Anchor | Typical position | Used by |
|---|---|---|
| `VFXAnchor` | Chest height, local `(0, 1.0, 0)` | `SkillVFX.play_on()` (as target) |
| `CombatTextAnchor` | Above head, local `(0, 1.8, 0)` | `CombatTextComponent` spawns floating text here (damage, heal, miss, parry, status, resist, etc.) |

Exact offsets are per-character (a small Skugge vs. a tall boss have different "above head"). Authored in the scene, not in code. Consumers call `get_anchor(kind)` on the character root and spawn their content there. No screen-space math.

```gdscript
# On CombatCharacter (class_name):
func get_anchor(kind: StringName) -> Node3D:
    match kind:
        &"vfx":         return vfx_anchor
        &"combat_text": return combat_text_anchor
    Log.error("CombatCharacter.get_anchor: unknown kind", kind, name)
    return null
```

**On miss:** logs via `Log.error` (hits Godot's Errors tab) and returns `null`. A missing anchor is an authoring mistake — the scene is missing a child node, and the corresponding visual (a VFX burst, a floating number) simply won't spawn. Obvious enough in play, loud enough in the console. Callers (`SkillVFX.play_on`, `CombatTextComponent`) should early-return if the anchor is `null` rather than crash.

---

## Token Visualization

`ActiveTokens` emits:
```gdscript
signal token_added(token: TokenData)
signal token_removed(token: TokenData)
signal token_updated(token: TokenData)   # stack count change, duration tick, etc.
```

`ActiveTokens` holds tokens and emits signals when they change. Consumers subscribe and draw. That's all.

Both players and enemies use `TokenDisplay.tscn` — the same scene instanced in their respective HUD card (`CombatCard` for players, `EnemyNameplate` for enemies). `ActiveTokens` on `combat_character` is the data source for both. There is no in-world token display.

**Layout and styling of `TokenDisplay.tscn`, `CombatCard`, and `EnemyNameplate` are defined in `2026-04-16-combat-hud-design.md`.**

---

## Event Flow & Orchestration

This section is the single source of truth for **who calls who, who emits what, and who subscribes to whom** across the combat visual layer. Everything else in this spec slots into the roles defined here.

### Layer responsibilities

| Layer | Role | Knows about | Never touches |
|---|---|---|---|
| **`CombatCalculator`** (static utility) | Pure math: given inputs, return an `AttackResult` | Stats, formulas, resistance tables | Signals, nodes, the scene tree |
| **`VitalsComponent`** (on character) | Dumb resource ledger — tracks `cur_hp`/`cur_mp`/`cur_ap` | Current values, mutation methods, raw change signals | Damage kinds, crits, outcomes, elements |
| **`ActiveTokens`** (on character) | Holds active tokens, emits add/remove/update signals | Tokens applied to this character | Anything outside its character |
| **Combat FSM** (the orchestrator — 6 states, see below) | State-machine driving the whole combat loop | FSM transitions, current turn context | Everything off the math/visual beat path |
| ↳ `FSMSTATE_ActionExecution` (one state of the FSM) | Runs a single resolved action: calls calculator, mutates vitals, drives visuals, emits bus events | Beat sequence for the current skill | Turn selection, combat start/end |
| **`CombatEvents`** (autoload bus) | Signal carrier, no logic | Only signal declarations | — |
| **`CombatVisuals`** (on character) | Plays animations, tweens position | Own sprite, own local position | Vitals, tokens, outcomes |
| **`CombatSFXComponent`** (on character) | Plays character-level audio | Own AudioStreamPlayer3D, own streams | Skill outcomes |
| **`CombatTextLayer`** (on combat scene) | Spawns floating text from resolution events | Bus outcomes, all character anchors | Vitals directly |
| **`TokenDisplay`** / **`CombatCard`** | Visual consumers of `ActiveTokens` + `VitalsComponent` | Own signals, own layout | Combat resolution |

**Combat FSM states** (detailed in a separate upcoming spec — listed here only so this doc's references make sense):

1. `FSMSTATE_CombatEntry` — scene mount, actor spawn, intro animations
2. `FSMSTATE_TurnStart` — pick next actor, tick tokens, apply DOTs/HOTs, `Guarding` clears
3. `FSMSTATE_ActionSelection` — player menu / AI decision, target picking
4. **`FSMSTATE_ActionExecution`** — **the only state that calls `CombatCalculator`, mutates vitals, and emits `attack_resolved` / `heal_resolved`.** This spec's canonical flow lives here.
5. `FSMSTATE_TurnEnd` — check for KO'd actors, check win/loss, advance turn index
6. `FSMSTATE_CombatExit` — outro, cleanup, return to overworld

Nothing outside `FSMSTATE_ActionExecution` calls the calculator. Nothing outside it mutates vitals from an attack. That's the containment.

### Signal inventory

**On `VitalsComponent` — pure change signals, no semantics:**
```gdscript
signal hp_changed(old: int, new: int)
signal mp_changed(old: int, new: int)
signal ap_changed(old: int, new: int)
```
Used by HP/MP/AP bars and by `combat_character._update_base_state()`. Not used by `CombatTextComponent`.

**On `ActiveTokens` — token lifecycle:**
```gdscript
signal token_added(token: TokenData)
signal token_removed(token: TokenData)
signal token_updated(token: TokenData)   # stack count / duration tick
```
Used by `CombatCard`, `TokenDisplay`, `CombatTextComponent` (for status/buff flourish).

**On `CombatEvents` (autoload bus) — combat resolution events:**
```gdscript
signal attack_resolved(target: CombatCharacter, result: AttackResult)
signal heal_resolved(target: CombatCharacter, amount: int)
signal actor_downed(actor: CombatCharacter)
# (More added as combat systems grow)
```
`AttackResult` shape — a `Resource`, not a Dictionary. Typed fields survive refactors, autocomplete works in the editor, and the class can grow (reflected damage, applied-ailment list, etc.) without retro-fitting callers:
```gdscript
class_name AttackResult
extends Resource

@export var outcome: AttackOutcome
@export var damage: int           # final damage (0 on MISS / PARRY / immune RESISTED)
@export var element: DamageType   # for VFX / text styling
```

The calculator **constructs and returns** a fresh `AttackResult.new()` per resolution. It is a transient carrier, never persisted to disk, never shared. Despite extending `Resource`, treat it as a value object: one result per attack, freed when its reference drops.

**`AttackOutcome` enum** (minimal, display-driven):
```gdscript
enum AttackOutcome {
    HIT,        # normal — text shows raw damage number, no label
    CRIT,       # critical — text shows damage + "CRIT!" flair, even on a weakness
    MISS,       # attack whiffed (covers dodge)
    PARRY,      # parried
    RESISTED,   # reduced or nullified (covers immune — a "0" damage reads as immune visually)
    WEAK,       # amplified damage
}
```
Per-outcome precedence when overlapping (e.g. crit on a weakness): **CRIT wins for display drama.** The resolver picks the single outcome to report. Damage math still accounts for both multipliers; the enum is display-only.

### Target reaction rule

The outcome determines what the **target's body** does during the strike-hold window:

| Outcome | Damage | Target reaction |
|---|---|---|
| `HIT` / `CRIT` / `WEAK` | > 0 | `play_hurt()` + VFX + damage text |
| `RESISTED` | > 0 | `play_hurt()` + VFX + damage text (number shows reduced amount) |
| `RESISTED` (immune) | 0 | `play_dodge_slide()` + text (no VFX, no hurt) |
| `MISS` | 0 | `play_dodge_slide()` + "Miss!" text (no VFX, no hurt) |
| `PARRY` | 0 | `play_dodge_slide()` + "Parry!" text (no VFX, no hurt) |

**Rule of thumb:** if `result.damage > 0`, play hurt; else, play the dodge slide. The text component handles the outcome-specific label on its own (it subscribes to the bus).

### Canonical single-attack flow

Step-by-step for one attacker using one skill on one target:

```
1. ActionExecution: decides attacker uses skill on target

2. ActionExecution: attacker.visuals.attack_to_motion_hold()        # await
3. ActionExecution: attacker.visuals.approach(offset)               # await

4. ActionExecution: result = CombatCalculator.resolve_attack(attacker, target, skill)
   (Calculator is pure — no side effects, no signals. Math in, result out.)
   Resolved BEFORE the strike so the controller knows which target reaction to run.

5. ActionExecution: attacker.sfx.play_swing()                       # fire-and-forget
6. ActionExecution: attacker.visuals.attack_to_strike_hold()        # await (sprite held at impact)

7. ActionExecution: CombatEvents.attack_resolved.emit(target, result)
   └── CombatTextComponent on target: filters target == get_parent(),
       spawns CombatText.tscn at CombatTextAnchor with result.outcome + result.damage

8. ActionExecution: if result.damage > 0:
       target.vitals.apply_damage(result.damage)                    # ledger mutation
         └── VitalsComponent emits hp_changed(old, new)
             └── HP bar UI tweens to new value
             └── combat_character._update_base_state() re-evaluates
       skill.vfx.play_on(target.get_anchor("vfx"))                  # await
       skill.sfx.play_on(target.sfx)                                # fire-and-forget
       await target.visuals.play_hurt()
   else:
       await target.visuals.play_dodge_slide()                      # no VFX, no apply_damage

9. ActionExecution: attacker.visuals.attack_to_recover_hold()       # await
10. ActionExecution: attacker.visuals.recover()                     # await
11. ActionExecution: attacker.visuals.attack_finish()               # await

12. ActionExecution: if target.vitals.cur_hp <= 0:
       await target.visuals.play_ko()
       CombatEvents.actor_downed.emit(target)
```

### Key architectural notes

- **Calculator stays pure.** No signals, no node, no state. `FSMSTATE_ActionExecution` emits `attack_resolved` on its behalf — this is deliberate: the calculator is a testable math function, and the bus emit is an orchestration concern that belongs to the state driving the action.
- **Vitals stays dumb.** It knows numbers, not outcomes. A `MISS` never reaches vitals — zero damage means no `apply_damage` call.
- **Text spawner reads the bus, not vitals.** `CombatTextComponent` does not subscribe to `hp_changed`. The semantic event is on the bus; the vitals mutation is downstream of it.
- **HP bars read vitals, not the bus.** A visual UI that cares about raw resource values subscribes to `hp_changed`. It doesn't care whether the change was a damage, heal, or cheat-mode resurrection.
- **Heal path is parallel.** `FSMSTATE_ActionExecution` emits `heal_resolved`, mutates vitals with `heal()`, text spawner shows heal number, HP bar tweens up.
- **Status/buff text uses `ActiveTokens` signals.** When a token is added with `show_on_apply = true`, `CombatTextLayer` subscribes to each character's `ActiveTokens.token_added` during setup and spawns the flourish at that character's anchor.

---

## Combat Text — `CombatTextLayer`

Floating text is a scene-level concern, not a per-character one. One `CombatTextLayer` node lives in the combat scene. It subscribes to the bus once, receives every resolution event, and spawns a `CombatText.tscn` instance at the relevant character's anchor. Multiple popups can be alive simultaneously — each is an independent scene instance that tweens itself and dies.

### What it covers

Every one-line piece of feedback that floats above a character:

- **Damage numbers** (`HIT`) — raw number, coloured by element
- **Crit numbers** (`CRIT`) — big number, `CRIT!` flourish, screen-shake optional
- **Heal numbers** — green
- **Accuracy misses** (`MISS`) — "Miss!" / "Parry!" labels, no number
- **Resistance outcomes** (`RESISTED` / `WEAK`) — coloured / labelled variants
- **Status / buff applied** — "Poisoned!", "Defend!", etc., when a token lands with `show_on_apply = true`

One node, one `CombatText.tscn`, many kinds of message. `CombatTextKind` drives the style.

```gdscript
enum CombatTextKind {
    DAMAGE,
    CRIT,
    HEAL,
    MISS,
    PARRY,
    RESISTED,
    WEAK,
    STATUS_APPLIED,
    BUFF_APPLIED,
}
```

### Contract

`CombatTextLayer` is **fully signal-driven**. No caller ever invokes it directly.

Subscribes in `_ready()` to:

1. **`CombatEvents.attack_resolved(target, result)`** — uses `target.get_anchor("combat_text")` directly. Maps `result.outcome` → `CombatTextKind`:
   - `HIT` → `DAMAGE`
   - `CRIT` → `CRIT`
   - `MISS` → `MISS`
   - `PARRY` → `PARRY`
   - `RESISTED` → `RESISTED`
   - `WEAK` → `WEAK`
2. **`CombatEvents.heal_resolved(target, amount)`** — uses `target.get_anchor("combat_text")` directly. Kind = `HEAL`.
3. **`ActiveTokens.token_added(token)` on each registered character** — connected during actor setup. If `token.show_on_apply == true`, spawns `STATUS_APPLIED` or `BUFF_APPLIED` at that character's anchor.

On each event, instantiates `CombatText.tscn` at the resolved anchor, passes in `{kind, value?, label?}`, lets the scene tween itself out and self-free.

**Never subscribes to `VitalsComponent`** — vitals is raw resource math; semantic outcomes live on the bus.

### Deferred

`CombatText.tscn` internals (layout, per-kind styling, tween curves, font, stacking behaviour) are deferred to their own mini-spec. The *contract above* is what the rest of the system builds against.

---

## Camera Integration (deferred)

Combat visuals do not drive the camera. A future `combat-camera` spec will define the controller that watches events on `CombatEvents` and pans/zooms accordingly.

**Reserved integration points:**
- Each `combat_character` is a valid camera anchor (`global_position`).
- `VFXAnchor` / `CombatTextAnchor` are valid camera anchors for tighter framing.
- The midpoint of all active enemy slots is the "enemy group" anchor; same for players.
- No camera code in this spec — just the promise that these anchors will exist and remain stable at the character root.

---

## Placeholder Art Policy

The system ships in full from day one. Art does not.

- Every animation slot (all 12) must exist on every combat character. It can be a single solid-coloured frame with a text label ("IDLE", "HURT", "KO'D", "GUARDING") — but the slot exists and the runtime plays it.
- Every skill ships with a `SkillVFX.tscn` scene and a `SkillSFX.tres` resource. The VFX can be a single coloured `GPUParticles3D` burst; the SFX can be a placeholder sine-wave beep. The scenes and resources exist.
- Every character ships with a `CombatSFX.tres`. Placeholder streams are fine.
- Token icons can be coloured squares with a letter. The `TokenDisplay` / `CombatCard` consumers are wired and functional.

We do not ship a partial architecture behind "we'll add that later." We ship a complete architecture behind placeholder assets.

---

## What Gets Deleted / Replaced in the Transition Plan

The combat transition plan (`2026-04-08-combat-transition.md`) currently has:

- **Task 8** — creates `CombatInputComponent` stub as a child of `combat_character`. **Delete.** Combat input is a scene-level concern (owned by the combat loop controller, not per-character). Separate spec when we get there.
- **Task 9** — "VisualComponent: combat adaptation." **Replace** with a pointer to this spec's implementation plan. The new task: build `CombatVisuals.tscn` skeleton per the API above.
- **Task 10** — `combat_character.tscn` currently instances overworld `VisualComponent.tscn`. **Change** to instance the new `CombatVisuals.tscn` and include the other new pieces: `CombatSFXComponent`, `ActiveTokens`, and the two world-space anchor nodes (`VFXAnchor`, `CombatTextAnchor`). `CombatTextLayer` is a separate node in the combat scene, not on `combat_character`. HUD cards (`EnemyNameplate`, `CombatCard`) are spawned by `CombatHUD` — not part of `combat_character`.

The overworld `VisualComponent` is **not touched** by this spec.

---

## Open Questions

Deliberately unresolved — address in follow-up specs, not here:

1. **Approach offset authoring.** Per-skill in the skill resource, or per-character? Probably per-skill with a per-character multiplier; defer until skill resource spec exists.
2. **`CombatText.tscn` internals.** Own mini-spec.
3. ~~**`TokenDisplay` visual layout.**~~ Resolved — see `2026-04-16-combat-hud-design.md`.
4. ~~**`CombatCard` visual layout.**~~ Resolved — see `2026-04-16-combat-hud-design.md`.
5. **Sprite sort order** when approach vectors overlap. Y-sort rule to be decided when it actually bites.
6. **Combat-level choreography** (group victory, all-KO fade, intro/outro sequencing). Combat loop controller's spec.
7. **Hurt interrupting an action clip.** Probably no — reactions queue. `FSMSTATE_ActionExecution`'s call.
8. **Mid-frame authoring format** — per-animation dictionary on `CombatVisuals` vs. a convention on `SpriteFrames`. Decide at implementation time.
9. **`Low_HP` threshold.** The example uses a `COMBAT_LOW_HP_THRESHOLD` constant; actual value needs a GDD entry alongside other combat thresholds.
10. **`AnimatedSprite3D.play()` resume semantics.** The `_resume_until_frame` / `_resume_to_end` helpers assume `play()` with no args resumes from a paused frame. If Godot 4 restarts the clip instead, swap to `speed_scale` toggling or similar. Verify during implementation.

---

## Next Steps

1. Write the companion implementation plan at `docs/superpowers/plans/2026-04-14-combat-visuals.md`.
2. Amend `2026-04-08-combat-transition.md`:
   - Delete Task 8 (`CombatInputComponent`).
   - Replace Task 9 with a pointer to the combat-visuals plan.
   - Update Task 10 to instance `CombatVisuals.tscn`, `CombatSFXComponent`, `TokenDisplay`, and the four root-level anchor `Node3D`s.
3. Follow-up specs (deferred): `CombatText`, `TokenDisplay`, `CombatCard`, `combat-camera`, per-skill VFX content guidelines.
