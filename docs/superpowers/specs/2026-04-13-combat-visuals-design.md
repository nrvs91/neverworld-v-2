# Combat Visuals — Design Spec
**Date:** 2026-04-13
**Status:** DRAFT — for discussion
**Scope:** How combat characters are displayed, animated, and decorated with skill VFX, status tokens, and damage feedback. No combat loop mechanics.

---

## Purpose

Define the visual subsystem for combat actors — what moves, what plays animations, what spawns VFX, what displays status — so that Task 9 of `2026-04-08-combat-transition.md` can be replaced with a clean, composable implementation instead of a null-guarded overworld adaptation.

This spec supersedes Task 9's "make `VisualComponent.controller` optional" approach. The existing overworld `VisualComponent` stays untouched.

---

## Guiding Principles

1. **Composition over sharing.** Overworld and combat visuals have almost no common behaviour. They share `AnimatedSprite3D` as a primitive and nothing else. Forcing a shared component leaks concerns both ways.
2. **Tiny character vocabulary, rich skill identity.** Every character has two combat-action animations (physical, cast) plus idle/hurt/death/victory. Skill identity lives in the VFX layer, not character animation.
3. **Static layout is a design feature, not a limitation.** Fixed camera, fixed positions, fixed facings. Halves the sprite workload, removes facing/rotation logic, makes anchors trivially authored.
4. **Sprite VFX for hero moments, particles for ambient only.** Pixel aesthetic coherence first.
5. **Signal-driven consumers.** `TokenContainer` emits; consumers (CombatCard UI, enemy TokenDisplay) subscribe. The container doesn't know who's listening.

---

## Scope

### In scope
- `CombatVisuals` scene — sprite + anchors + token display, owned by `CombatCharacter`
- Character animation vocabulary (attack/cast startup/recovery + idle/hurt/death/victory)
- Anchor nodes for VFX, damage popups, nameplates, tokens
- `SkillVFX` resource pattern — sprite-based one-shot VFX spawned at anchors
- Token visualization asymmetry (players → `CombatCard` UI, enemies → in-world `TokenDisplay`)
- Approach/recover movement (local position tween during action)
- Damage popup spawn API

### Out of scope
- Combat loop / turn controller / action sequencer (consumer of this API, not part of it)
- Skill resource shape (references a `SkillVFX`, but skill data itself is a separate spec)
- `CombatCard` UI layout and styling (separate UI spec)
- Camera behavior (static; no work needed)
- Overworld `VisualComponent` — explicitly unchanged
- Ultimate / limit-break bespoke animations (backdoor API reserved, not designed yet)

---

## Layout Assumptions

The combat scene is statically laid out:

- **Camera** is fixed, orthographic, the existing 640×360 SubViewport pipeline.
- **Players** occupy the lower-right of the frame, sprites rendered **back-view** (camera sees their backs).
- **Enemies** occupy the upper-left of the frame, sprites rendered **front-view** (camera sees their faces).
- Both parties face each other along a diagonal axis. Neither party rotates or turns during combat.
- Slot positions are authored in `PlayerSpawner.tscn` and `EnemySpawner.tscn` (already planned).

**Consequences:**
- Sprite sheets per character need only one facing direction (back for players, front for enemies). Half the art budget of a 4-directional system.
- No `face()` API on `CombatVisuals`. If a displacement effect ever needs a flip, it's a local `sprite.flip_h` at that moment — not core infrastructure.
- Approach motion is a straight tween along a known vector. No pathing, no rotation.

---

## Scene Shape

### `CombatCharacter.tscn` (revised)

```
CombatCharacter (Node3D)                — sits at slot, NEVER moves
  ├── VitalsComponent                   — cur_hp / cur_mp / cur_ap
  ├── TokenContainer                    — holds tokens, emits add/remove signals
  └── CombatVisuals (Node3D)            — the visual subsystem; tweens its own local position during actions
        ├── AnimatedSprite3D            — the character sprite
        ├── VFXAnchor (Node3D)          — where skill VFX spawn (e.g. chest height)
        ├── DamagePopupAnchor (Node3D)  — where damage numbers spawn (above head)
        ├── NameplateAnchor (Node3D)    — where enemy nameplate mounts (above head, enemies only use it)
        └── TokenDisplay                — listens to parent CombatCharacter's TokenContainer, spawns icons at a TokenAnchor; visibility flag off for players
```

**Why `CombatVisuals` owns its own position:** during approach/recover, only the visual representation moves. The `CombatCharacter` root stays at its authored slot — that's the combatant's "home," and it's where targeting, anchor math from outside, and post-action return all reference. `CombatVisuals` tweens its local position from `Vector3.ZERO` to the target offset and back. Anchors are children of `CombatVisuals`, so they ride along.

**Why scene is symmetric player/enemy:** The only asymmetry is which consumer is wired to `TokenContainer`. Players' `TokenDisplay` stays hidden; their tokens render on `CombatCard`. Enemies' `TokenDisplay` is visible. Keeps a single `CombatCharacter.tscn` for both — no scene fork.

---

## Character Animation Vocabulary

Per character, the following `SpriteFrames` animations are required:

| Animation | Loop | Purpose |
|---|---|---|
| `Idle` | yes | Default pose, subtle sway optional |
| `Attack_Startup` | no | Wind-up + strike; **final frame is the held pose** |
| `Attack_Recovery` | no | Hop back / return-to-neutral after a physical action |
| `Cast_Startup` | no | Cast wind-up; **final frame is the held pose** |
| `Cast_Recovery` | no | Return-to-neutral after a cast |
| `Hurt` | no | Flinch on taking damage |
| `Death` | no | Fall / dissolve; final frame is the "downed" pose |
| `Victory` | yes or no | Optional — triumph pose post-battle |

**Why split startup/recovery:** `AnimatedSprite3D` auto-holds the last frame when `loop = false`. So after `Attack_Startup` finishes, the character naturally sits on the swung pose while VFX plays — no pause hacks, no frame counting. `Attack_Recovery` is a separate clip triggered when the sequencer is ready to move on.

**Why only two action anims:** Every physical skill (HEW, ONSLAUGHT, SLASH, CLEAVE, etc.) plays `Attack_Startup` / `Attack_Recovery`. What makes them visually distinct is the `SkillVFX` that plays during the held-pose window. Same for casts: one generic wind-up, unique VFX per spell. This matches classic JRPG conventions (FF4–6, Breath of Fire, Suikoden) and dramatically reduces per-character art cost.

**Backdoor for exceptions:** `CombatVisuals.play_custom(anim_name)` exists for the rare bespoke case (ultimates, limit breaks, scripted moments). Not used in the baseline pipeline.

---

## `CombatVisuals` API

Thin, signal-driven, await-friendly. Each method is an atom; the turn controller composes them.

```gdscript
class_name CombatVisuals
extends Node3D

# --- Setup ---
func setup(sprite_frames: SpriteFrames) -> void
  # Assigns SpriteFrames to the AnimatedSprite3D, plays Idle.

# --- Movement (local position tween) ---
func approach(target_offset: Vector3, duration: float = 0.2) -> void
  # Tweens local position from ZERO to target_offset. Awaits tween completion.

func recover(duration: float = 0.2) -> void
  # Tweens local position back to ZERO. Awaits tween completion.

# --- Action animations ---
func attack_strike() -> void
  # Plays Attack_Startup. Awaits animation_finished. Sprite holds final frame after.

func attack_recovery_anim() -> void
  # Plays Attack_Recovery. Awaits animation_finished. Blends back to Idle.

func cast_strike() -> void
  # Plays Cast_Startup. Awaits animation_finished. Sprite holds final frame.

func cast_recovery_anim() -> void
  # Plays Cast_Recovery. Awaits animation_finished. Blends back to Idle.

# --- Reactions ---
func play_hurt() -> void
  # Plays Hurt, awaits completion, returns to Idle.

func play_death() -> void
  # Plays Death, awaits completion, holds final frame. No return to Idle.

# --- Feedback ---
func spawn_damage_popup(text: String, color: Color) -> void
  # Instantiates a DamagePopup at DamagePopupAnchor. Non-blocking.

# --- Anchors ---
func get_anchor(kind: StringName) -> Node3D
  # "vfx" -> VFXAnchor, "popup" -> DamagePopupAnchor, "nameplate" -> NameplateAnchor, "token" -> TokenAnchor

# --- Escape hatch ---
func play_custom(anim_name: String) -> void
  # For bespoke animations (ultimates, scripted). Awaits completion.
```

**A canonical action sequence (composed by the turn controller):**

```gdscript
# HEW: physical attack with an impact-burst VFX
var target_pos: Vector3 = target.position - attacker.position  # local offset from attacker

await attacker.visuals.approach(target_pos)
await attacker.visuals.attack_strike()                          # sprite ends on held pose
await skill.vfx.play_on(target.visuals.get_anchor("vfx"))       # VFX plays to completion
await attacker.visuals.attack_recovery_anim()                   # hop back sprite
await attacker.visuals.recover()                                # position tween home
await target.visuals.play_hurt()
target.visuals.spawn_damage_popup(str(damage), Color.WHITE)
```

Seven lines, seven beats. Each beat is independently tunable.

---

## Skill VFX

VFX is data. Each skill references a `SkillVFX` resource, which points at a `PackedScene`.

### `SkillVFX.gd`
```gdscript
class_name SkillVFX
extends Resource

@export var scene: PackedScene  # scene containing an AnimatedSprite3D
@export var duration_hint: float = 0.0  # optional, for cases where self-free timing isn't enough
```

### `SkillVFX.tscn` shape (per-skill asset)
```
SkillVFX (Node3D, script attached)
  └── AnimatedSprite3D — plays once; queue_free()s the root on animation_finished
```

### Playback API
```gdscript
# On SkillVFX resource
func play_on(anchor: Node3D) -> void:
    var instance: Node3D = scene.instantiate()
    anchor.add_child(instance)
    await instance.tree_exited
```

**Why sprite-based, not particles:** Pixel aesthetic coherence. A hand-authored 8-frame impact burst reads as "hit" in a way particle sparks can't. Authoring workflow is unified with character sprites (same Aseprite pipeline, same SpriteFrames muscle memory).

**Where particles DO earn their keep:** ambient continuous effects only — dust from a dash, embers rising from a fire, smoke from a destroyed enemy. Never as the "hero effect" of a skill. Rule of thumb: **hero = sprite, ambient = particles, never mix metaphors inside one skill.**

---

## Anchors

Anchors are authored `Node3D` children of `CombatVisuals` at offsets that make sense for the character:

| Anchor | Typical position | Used by |
|---|---|---|
| `VFXAnchor` | Chest height, local `(0, 1.0, 0)` | `SkillVFX.play_on()` (targeted) |
| `DamagePopupAnchor` | Above head, local `(0, 1.8, 0)` | `spawn_damage_popup()` |
| `NameplateAnchor` | Above head, local `(0, 2.0, 0)` | Enemy nameplate UI mount |
| `TokenAnchor` | Above head / beside head, local `(0.4, 1.6, 0)` | Enemy `TokenDisplay` |

Exact offsets are per-character (a small Skugge vs. a tall boss have different "above head"). Authored in the scene, not in code. Consumers ask `get_anchor("vfx")` and spawn their content there. No screen-space math anywhere.

---

## Token Visualization

`TokenContainer` (on `CombatCharacter`) emits:
```gdscript
signal token_added(token: TokenData)
signal token_removed(token: TokenData)
signal token_updated(token: TokenData)   # stack count change, duration tick, etc.
```

Consumers subscribe based on who the character is:

### Players — `CombatCard` (UI layer)
- `CombatCard` is spawned by the combat UI layer, one per party slot.
- Card subscribes to the slot's `TokenContainer` signals.
- Tokens render as icons in a row on the card, next to HP/AP bars.
- The in-world `TokenDisplay` on the player's `CombatVisuals` is **invisible** (visibility flag off) — redundant with the card.

### Enemies — `TokenDisplay` (in-world)
- `TokenDisplay` is a small node that lives under `CombatVisuals` as a child.
- Subscribes to its parent `CombatCharacter`'s `TokenContainer`.
- Spawns small icon sprites at `TokenAnchor`, arranged horizontally.
- Updates/removes icons as signals fire.
- Visible for enemies.

**Why not fork the scene:** The only difference between player and enemy is a visibility flag. A scene fork for a single bool is overkill. If the asymmetry grows, revisit.

---

## What Gets Deleted / Replaced in the Transition Plan

The combat transition plan (`2026-04-08-combat-transition.md`) currently has:

- **Task 8** — creates `CombatInputComponent` stub as a child of `CombatCharacter`. **Delete.** Combat input is a scene-level concern (owned by the combat loop controller, not per-character). That's a separate spec.
- **Task 9** — "VisualComponent: combat adaptation." **Replace** with a new task: "Build `CombatVisuals.tscn` skeleton" — scene tree, anchors, `setup()` + `play()` stubs, no VFX/Token logic yet.
- **Task 10** — `CombatCharacter.tscn` currently instances overworld `VisualComponent.tscn`. **Change** to instance the new `CombatVisuals.tscn`. Remove `CombatInputComponent` child.

The overworld `VisualComponent` is **not touched** by this spec. It keeps its `controller` export, its `direction_changed` / `run_toggled` connections, and its current behaviour.

---

## Open Questions

Things deliberately unresolved — to iron out in review:

1. **Approach offset authoring.** Per-skill in the skill resource, or per-character (some characters always dash closer than others)? Suggest per-skill with a per-character multiplier, but defer until skill resource spec exists.
2. **Damage popup scene.** Out-of-scope here or worth sketching? A `DamagePopup.tscn` with a tween + label is 10 lines but deserves a one-paragraph API definition somewhere.
3. **`TokenDisplay` layout.** Horizontal row, grid, stack? Assume row for now; revisit if enemies routinely carry 5+ tokens.
4. **Sprite sort order.** Players in front or enemies in front when approach vectors overlap? Attacker on top during their action seems right, but needs a `z_index` / Y-sort rule.
5. **Victory / defeat group sequencing.** Does each character play `Victory` independently, or is there a combat-level choreographer? Probably the latter, but not this spec's problem.
6. **Hurt interrupts held pose?** If an attacker is mid-`Attack_Startup` and gets hit by a reaction, does `Hurt` override? Probably yes — turn controller's decision, not the API's.

---

## Open Decision Points (need input)

Things I have a lean on but want your sign-off:

- **Naming:** `CombatVisuals` as the component. Alternatives: `BattleVisuals`, `CombatCharacterVisuals`. I prefer `CombatVisuals` — short, domain-clear.
- **Leave overworld `VisualComponent` as-is:** No renaming. The file sits in `scripts/characters/` and works. If we ever touch it, that's a separate cleanup task.
- **`TokenDisplay` always present:** Included in `CombatVisuals.tscn`, visibility flipped at setup time. Alternative is scene fork — not worth it yet.
- **Sprite VFX as default:** Particles only for ambient. Codified in the spec so it's a rule, not a preference.

---

## Next Steps (once spec is agreed)

1. Revise `2026-04-08-combat-transition.md`:
   - Delete Task 8's `CombatInputComponent`
   - Replace Task 9 with "Build `CombatVisuals` skeleton"
   - Update Task 10 to instance `CombatVisuals` instead of overworld `VisualComponent`
2. Author a placeholder `CombatVisuals.tscn` with anchors and stub methods.
3. Wire Skugge's combat sprite (back-view SpriteFrames) to verify the pipeline end-to-end.
4. Defer all of: `SkillVFX` resource, `DamagePopup`, `TokenDisplay` implementation to follow-up specs once the skeleton runs.
