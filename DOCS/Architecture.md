# NEVERWORLD — Architecture

> This document describes how systems connect and talk to each other.
> It is not a design document — see GDD_V2.md for that.
> Update this as systems are built and flows are confirmed.

---

## Data Layer

Game data lives in Resources (`.tres` files). Nodes read from resources — they do not own the data.

### Character Data Hierarchy

```
CharacterData          ← identity only (name, ID, portrait, sprite)
  ├── CombatData       ← adds base stats (HP, MP, AtkPhys, etc.)
  │     ├── PlayerData ← adds growth table, allowed gear
  │     └── EnemyData  ← (future) adds loot table, AI profile, resistances
  └── NPCData          ← (future) adds dialogue, quest flags
```

### Supporting Resources

```
GrowthTable            ← array of GrowthEntry rows (one per level above 1)
GrowthEntry            ← per-level stat deltas for one level-up
CharacterSaveData      ← mutable per-character state (see Save Layer)
EquipmentType          ← flags enum for weapon/armor type constraints
```

---

## Save Layer

One `SaveFile` resource holds everything that persists to disk.

```
SaveFile
  ├── party_data: PartyData          ← active party slots, shared RESONANCE
  ├── character_saves: Dictionary    ← character_id → CharacterSaveData
  └── (future) world state, flags, etc.
```

### CharacterSaveData

Holds everything that changes over a playthrough for one character:

- `cur_hp`, `cur_mp` — current resources
- `character_level`, `cur_xp` — progression
- `equipped_weapon_id`, `equipped_armor_id`, `equipped_gear_ids` — gear slots
- `equipped_mnemonic_ids` — 4 mnemonic slots
- `choice_bonuses` — accumulated stat picks (Dictionary: stat → bonus)
- `stat_last_chosen_level` — cooldown tracking for choice growth

### Creating a new CharacterSaveData

When a character joins the party (game start or mid-story), a static factory function seeds a fresh `CharacterSaveData` from the character's `PlayerData` template:

```
CharacterSaveData.create_for(player_data: PlayerData) -> CharacterSaveData
```

---

## Stat Computation

Final stats are never stored — always computed on demand from two sources:

```
PlayerData (template)     +     CharacterSaveData (save state)
  └── base stats                  └── level, choice bonuses, gear IDs
  └── growth table
          ↓
     StatCalculator (static utility)
          ↓
     final stat block
```

`StatCalculator` is a pure utility — static functions, no state, no node. Called by UI to display stats, called by `CombatStart` state to initialize combat actors.

---

## Overworld

```
overworld_character.tscn
  ├── PlayerInputComponent / NPCBehaviorComponent   ← reads input or AI, emits direction_changed / run_toggled / interact_pressed
  ├── MovementComponent      ← listens to direction_changed, run_toggled — moves the character
  └── VisualComponent        ← listens to direction_changed, run_toggled — drives AnimatedSprite3D
```

- `overworld_character.gd` wires `controller` on both `MovementComponent` and `VisualComponent` at `_ready()`
- Also passes `character_data` to `VisualComponent` so it can assign the correct `SpriteFrames` to `AnimatedSprite3D`
- For NPCs, `PlayerInputComponent` is swapped for `NPCBehaviorComponent` — other components don't notice
- Camera is fixed — input is rotated 45° in `MovementComponent` to match isometric orientation

## Exploration / Zones

Zones are scenes built from `zone_template.tscn` — a plain `Node` tree with placeholder containers. Creating a new zone means duplicating the template and populating the exports.

### Zone Scene Anatomy

```
Zone (Node)
├── System (Node, process_mode=3)          ← never pauses, even during combat
│   └── WorldEnvironment                   ← per-zone lighting, sky, ambient
├── ExplorationSetup (instance)            ← orchestrates exploration lifecycle
│   ├── ExplorationBGM (AudioStreamPlayer) ← zone music, stream set per-zone
│   └── ExplorationEnvironment (Node)      ← loads 3D geometry on enter()
│         scene: PackedScene               ← set per-zone to the .glb/.fbx geometry
├── CombatSetup (instance)                 ← orchestrates combat trigger flow
│   ├── StepCounter
│   ├── EncounterPool
│   ├── CombatEnvironment                  ← battle background, scene set per-zone
│   └── CombatBGM
├── SpawnPoints (Node)
│   └── default (Marker3D)                 ← at least one required per zone
├── NPCs (Node)                            ← container
├── Items (Node)                           ← container
├── Triggers (Node)
│   └── ZoneExit (Area3D)                  ← fires zone_exit_requested on enter
└── Puzzles (Node)                         ← container
```

### Dual `@tool` Requirement

Both `ExplorationSetup` and `ExplorationEnvironment` carry the `@tool` annotation. This is required for geometry to appear in the editor — neither annotation can be omitted.

- **`ExplorationSetup`** — `_ready()` detects `Engine.is_editor_hint()` and calls `exploration_environment.enter()` to load preview geometry. At runtime, `_ready()` skips this path; GameManager calls `enter()` later.
- **`ExplorationEnvironment`** — needs `@tool` so it is not treated as a placeholder instance. If only `ExplorationSetup` has `@tool`, Godot throws "Attempt to call a method on a placeholder instance" because the child's script is not compiled for the editor.

### Zone Lifecycle

```
GameManager._load_zone()
  ├── zone.instantiate() → add to CurrentScene
  ├── setup = instance.get_node("ExplorationSetup")
  ├── setup.enter()
  │     ├── exploration_environment.enter()   ← instantiates geometry from scene export
  │     └── exploration_bgm.play()
  └── spawn pawn at SpawnPoints/<spawn_point>

GameManager._unload_zone()
  └── setup.exit()
        ├── exploration_environment.exit()    ← queue_free() geometry
        └── exploration_bgm.stop()
```

During combat transitions: `pause_for_combat()` hides geometry (`.visible = false`) without freeing it. `resume_after_combat()` shows it again. The `System` node's `process_mode = 3` ensures `WorldEnvironment` keeps rendering even while the rest of the zone is paused.

### Authoring a New Zone

1. Duplicate `zone_template.tscn` and rename.
2. Set `WorldEnvironment` properties (background color, ambient light) per-zone.
3. Set `ExplorationEnvironment.scene` to the 3D geometry for this zone.
4. Set `ExplorationBGM.stream` to the zone's music.
5. Add spawn points as `Marker3D` children of `SpawnPoints` — at least a `default`.
6. Add `ZoneExit` triggers under `Triggers` with `target_zone_path` pointing to the destination.
7. Optionally configure `CombatSetup` (encounter pool, combat background, combat BGM).
8. Ensure `[editable path="ExplorationSetup"]` and `[editable path="CombatSetup"]` are present for property override support.

Zone geometry is never baked as a direct child — it always lives inside `ExplorationEnvironment.scene`. This keeps the same zone scene usable in both exploration and combat (geometry is hidden during battles).

### Running a Zone Without Combat

If a zone should not trigger random encounters, omit all children of `CombatSetup` (StepCounter, EncounterPool, CombatEnvironment, CombatBGM). The `CombatSetup` instance is inert with no children to orchestrate.

---

## Combat Characters

Overworld and combat are separate representations of the same character data. They share components where it makes sense but are distinct scenes with distinct purposes.

```
combat_character.tscn
  ├── VisualComponent        ← reused from overworld — same sprite, same animation logic
  ├── CombatInputComponent   ← waits for player menu input (replaces movement input)
  └── CombatComponent        ← owns runtime combat state: cur_hp, cur_mp, cur_ap, tokens, is_downed
```

- `VisualComponent` is the same component as overworld — reads `character_data.character_sprite`, drives `AnimatedSprite3D`
- `CombatComponent` is combat-only — handles HP/MP/AP tracking, token list, downed state
- All `combat_character` instances are identical in structure — what differs is the `CharacterData` resource attached
- Player instances seed from `PlayerData` + `CharacterSaveData` via `StatCalculator`
- Enemy instances seed from `EnemyData` directly — no save data involved

---

## Combat

Combat runs in a **dedicated battle scene** — separate from the overworld. The overworld freezes, the battle scene loads, the fight resolves, the player returns.

### Two FSMs + ActionPipeline

```
Logic FSM → ActionPipeline ←→ (event bus) ←→ UI FSM
```

- **Logic FSM** owns turn order and state transitions — a pure state pump. No damage math, no resource logic.
- **ActionPipeline** owns the action resolution cycle — announce, pre-reactions, primary execution, post-reactions, downed checks, resource spend. Called by Logic FSM, awaits `pipeline_complete` before transitioning.
- **UI FSM** owns presentation — animations, floating numbers, bar updates.
- FSM and UI never touch each other directly — all communication through `CombatEvents` bus.
- ActionPipeline communicates with UI through the same bus (`action_announced`, `action_resolved`, `actor_downed`).

### Combat Actors

See **Combat Characters** section above. `combat_character.tscn` is the combat actor — same scene for players and enemies, different `CharacterData` resource attached to each.

### Combat Initialization Flow

```
CombatStart state
  ├── for each party member: pull PlayerData + CharacterSaveData → StatCalculator → spawn CombatActor
  ├── for each enemy: pull EnemyData → spawn CombatActor
  └── emit CombatStarted → UI FSM takes over presentation
```

---

## Token System

The token system models all combat effects — damage, DoT, buffs, debuffs, marks, reactions — as first-class runtime objects. Every effect flows through a unified token lifecycle.

### RuntimeToken Hierarchy

Tokens are `RefCounted` instances spawned by `SkillExecutor` from mnemonic effect data. Each token carries:
- **token_type**: Display/deduplication key (e.g. `"POISON"`, `"BURN"`, `"DAMAGE"`)
- **trigger**: When the token fires — `INSTANT`, `ON_TURN_START`, `ON_DAMAGE_TAKEN`, `ON_ALLY_HIT`, `PRE_EXECUTION`
- **charges**: Decrement counter; token expires when charges ≤ 0
- **source** / **owner**: The attacker and target `CombatCharacter`

```
RuntimeToken (base)
  ├── RuntimeToken_Damage   ← INSTANT — hit/crit/resist pipeline, applies damage, emits action_executed
  ├── RuntimeToken_DoT      ← ON_TURN_START — ticks per GDD formula, emits dot_ticked
  └── (future) RuntimeToken_Buff, RuntimeToken_Ailment, RuntimeToken_Mark
```

**Two dispatch paths:**

- **INSTANT** (`RuntimeToken_Damage`): `fire(context)` runs immediately during mnemonic resolution. Result written to `ActionContext` via `record_step()`. Token does not persist.
- **Persistent** (`RuntimeToken_DoT`, future): Added to `CombatCharacter.tokens` (`ActiveTokens` container). `tick()` called each turn. Charges decrement; token auto-expires at 0.

**Passive vs Reaction:**

Not every token that responds to combat activity is a "reaction." The pipeline's PRE/POST passes are for tokens that genuinely need a **before/after window** around the primary action. Everything else is **passive state** that damage resolution reads inline.

| Token | Type | Where It Lives |
|---|---|---|
| **COVER / INTERCEPT** | Passive | `RuntimeToken_Damage.fire()` — target resolution step. Redirect effects from protectee to protector. |
| **BRACE / Shield** | Passive | `RuntimeToken_Damage.fire()` — damage calc step. "Reduce damage by X%" modifies the number inline. |
| **COUNTER** | POST reaction | ActionPipeline post-pass. "If you hit me, I hit back" — needs primary to resolve first. |
| **HAMEDO** | PRE reaction | ActionPipeline pre-pass. "Hit first before they hit you" — may kill attacker to cancel action. |
| **PREMONITION** | PRE reaction | ActionPipeline pre-pass. Nullifies incoming spell; sets `context.negated = true`. |
| **VIGIL** | POST reaction | ActionPipeline post-pass. "When ally takes damage, heal them" — needs primary to resolve. |
| **FOLLOW UP** | POST reaction | ActionPipeline post-pass. "When ally hits enemy, I hit too" — same window as VIGIL. |

**Rule:** If the effect can be described as "modify how Z works" or "redirect from A to B," it's passive state. If it's "when X happens, do Y," it's a reaction that belongs in a pass.

### Action Resolution Flow

```
CombatFSM._enter_action_execution()
  └── ActionPipeline.run(mnemonic, attacker, target, actors)
        ├── Create ActionContext
        ├── Emit action_announced → hold 0.5s for presentation
        ├── PRE-PASS: iterate all actors' tokens for PRE_EXECUTION triggers
        │     └── Each reaction fires with fresh context (trigger_context → primary)
        ├── VALIDATE: attacker alive? AP/MP sufficient? negated?
        ├── Spend AP/MP (only if validation passes)
        ├── SkillExecutor.execute(context)  ← primary action
        │     └── For each effect in mnemonic.effect_steps:
        │           ├── Check needs_previous_hit vs context.any_hit
        │           ├── _create_token(effect, attacker, target)
        │           ├── INSTANT  → token.fire(context)
        │           └── Persistent → target.tokens.add_token(token)
        ├── Spend hp_cost_percent (if any)
        ├── Check primary target downed
        ├── POST-PASS: iterate all actors' tokens for ON_DAMAGE_TAKEN / ON_ALLY_HIT
        │     └── Each reaction fires with fresh context (trigger_context → primary)
        ├── Emit action_resolved(context)
        └── Emit pipeline_complete → FSM transitions to TURN_END
```

**Key rules:**
- Validation happens **after** pre-pass, **before** resource spend. Pre-reactions (HAMEDO) can down the attacker; if so, action is `cancelled` — no AP/MP spent.
- If a PRE reaction negates the action (PREMONITION), action is `negated` — AP/MP **are** spent.
- Reactions fire with their own clean `ActionContext`. `trigger_context` points to the primary action's context so reactions can read `attacker`, `any_hit`, `total_damage`, etc.
- Post-queue is built from the primary context only. Reaction attacks do not trigger further reactions — one level deep per GDD spec.

### DoT Tick Formulas

Fixed per `dot_tag` — not authored per instance:

```
POISON: (max_hp × 10% + max_mp × 10%) × resist_multiplier
BURN:   max_hp × 10% × resist_multiplier
BLEED:  max_hp × 10% × resist_multiplier
```

IMMUNE targets (resist_multiplier == 0): tick skipped silently, charges still decrement.

DoT stacking: re-application extends existing token charges (capped at 9) rather than creating a duplicate.

### ActionContext — Execution Snapshot

Created by `ActionPipeline` before any effects resolve. Reactions get their own fresh `ActionContext` with `trigger_context` pointing back to the primary.

```
ActionContext
  ├── mnemonic, attacker, primary_target   ← set by ActionPipeline
  ├── step_results: Array                  ← {hit, damage, is_crit} per effect step
  ├── tokens_applied: Array                ← persistent tokens queued this execution
  ├── total_damage, any_hit, any_crit      ← rolling totals; any_hit only set by INSTANT hits
  ├── trigger_context: ActionContext       ← set on reaction contexts; points to primary action
  ├── negated: bool                        ← set by PRE reaction (e.g. PREMONITION)
  ├── cancelled: bool                      ← set by ActionPipeline when validation fails
  ├── pre_queue: Array                     ← RuntimeTokens collected during pre-pass
  └── post_queue: Array                    ← RuntimeTokens collected during post-pass
```

---

## Skill Data Layer

Skills are authored as `.tres` resources. No skill logic lives in code — only data.

### MnemonicResource

One skill's complete definition:

```
MnemonicResource
  ├── mnemonic_name, rank, is_melee, merge_display
  ├── ap_cost, mp_cost, hp_cost_percent
  ├── targeting: TargetingData              ← shape (SINGLE/ALL/SELF) + filter (HAS_DOT, IS_DOWNED)
  └── effect_steps: Array[Skill_Effect_Base] ← ordered list; SkillExecutor iterates in order
```

### Skill_Effect_Base Hierarchy

```
Skill_Effect_Base (Resource)
  ├── chance_tier: ChanceTier    ← CERTAIN/HIGH(75%)/MEDIUM(50%)/LOW(25%)
  ├── needs_previous_hit: bool   ← skip if prior step missed
  ├── true_strike: bool          ← bypass hit roll entirely
  ├── Skill_Effect_Damage        ← power, damage_type, crit_chance, inherit_from_weapon
  └── Skill_Effect_DoT           ← dot_tag (POISON/BURN/BLEED), charges
```

**ChanceTier semantics by effect type:**
- Physical damage: scales attacker HIT in `clamp((HIT × tier%) / DODGE, 5%, 95%)`
- Magical damage / heals / buffs: ignored — always connects
- Ailments (future): raw application probability before resistance

---

## Combat FSM States

The Logic FSM drives turn-by-turn combat. No UI concerns — all presentation via `CombatEvents` bus.

```
COMBAT_START → TURN_START ←────────────────────┐
                   ↓                            │
              ACTION_SELECT                     │
                   ↓                            │
            ACTION_EXECUTION                    │
                   ↓                            │
               TURN_END ────────────────────────┘
                   ↓ (all enemies OR all players dead)
               COMBAT_END
```

| State | Responsibility |
|-------|----------------|
| **COMBAT_START** | Emit `combat_started`. Transition to TURN_START. |
| **TURN_START** | Advance turn tracker, award AP, tick active actor's ON_TURN_START tokens (DoT etc.), emit `turn_started`. |
| **ACTION_SELECT** | Player: await `action_selected` signal. Enemy: AI picks target + mnemonic. WAIT → TURN_END. |
| **ACTION_EXECUTION** | Delegate to `ActionPipeline.run()`. Await `pipeline_complete`. Transition to TURN_END. |
| **TURN_END** | Consume CT. Emit `turn_ended`. Wait for presentation. Check combat end. Loop to TURN_START. |
| **COMBAT_END** | Emit `combat_ended(player_won)`. Suspend. |

**Known gaps (to address before they become load-bearing):**
- `TargetingData.shape` is authored but not yet consumed by SkillExecutor or CombatUIFSM
- Hardcoded `create_timer()` delays stand in for a `presentation_finished` signal that doesn't exist yet
- Reaction token subclasses (COUNTER, HAMEDO, PREMONITION, VIGIL, FOLLOW UP) are not yet implemented — pipeline infrastructure is wired, queues are always empty

---

## Event Buses

Cross-system communication uses domain-specific autoload event buses — signal declarations only, no logic.

| Bus | Domain |
|-----|--------|
| `CombatEvents` | Combat lifecycle signals |

Rules:
- Cache bus references in `_ready()`
- Always disconnect in `_exit_tree()`
- Use direct signals for parent↔child within the same scene
- Split buses by domain — never one mega-bus
