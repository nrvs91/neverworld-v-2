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

The token system models all combat effects — damage, DoT, buffs, debuffs, reactions, finishers — as first-class runtime objects. Every effect flows through a unified token lifecycle.

### RuntimeToken

`RuntimeToken` extends `Resource`. Each instance carries:
- **token_type** — string key for deduplication and UI display (`"POISON"`, `"EMPOWER"`, etc.)
- **trigger** — when the token fires (see table below)
- **source** / **owner** — the initiating and receiving `CombatCharacter`
- **opposes** — if set, adding this token cancels one existing instance of that type rather than stacking
- **skip_first_tick** — if true, the first ON_TURN_END tick is a no-op (grants self-buffs a free cast turn)

**Trigger enum:**

| Trigger | When it fires |
|---------|--------------|
| `INSTANT` | Immediately on creation — fires and discards, never stored in ActiveTokens |
| `ON_TURN_START` | Start of the owner's turn — DoT ticks, CC expiry |
| `ON_TURN_END` | End of the owner's turn — buff/debuff expiry |
| `ON_DAMAGE_TAKEN` | POST-pass — owner was the damage target this action |
| `ON_ALLY_HIT` | POST-pass — an ally on the same team took damage this action |
| `PRE_EXECUTION` | PRE-pass — fires before the primary action resolves |

### Quantity Model

Tokens use a **quantity-as-duration** model — no charges counter. "3 POISON" means three separate `RuntimeToken_Poison` instances in `ActiveTokens`. Each tick consumes one instance. 3 POISON → 3 ticks → 3 turns of DoT.

The same model applies to buffs and debuffs: 3 EMPOWER = 3 instances, one expires per TurnEnd. The count visible in the UI is a live instance count, not a counter field.

### RuntimeToken Hierarchy

```
RuntimeToken (Resource)
  ├── RuntimeToken_Damage     — INSTANT: hit roll, crit, resist pipeline; standard attack damage
  ├── RuntimeToken_Envenom    — INSTANT: consume_all(type), damage = count × power_per_token
  ├── RuntimeToken_Poison     — ON_TURN_START: Nature DoT tick
  ├── RuntimeToken_Empower    — ON_TURN_END: ×1.5 damage multiplier; opposes WEAKEN; skip_first_tick
  ├── RuntimeToken_Weaken     — ON_TURN_END: ×0.75 damage multiplier; opposes EMPOWER
  ├── RuntimeToken_Stun       — consumed by CombatFSM at TurnStart to skip AP gain and ACTION_SELECT
  ├── RuntimeToken_Counter    — ON_DAMAGE_TAKEN: retaliates against attacker
  └── RuntimeToken_Vigil      — ON_ALLY_HIT: heals the ally that took damage
```

### Passive Hooks

Tokens can expose passive effects polled inline during damage resolution without needing a trigger window:

- `get_damage_multiplier() -> float` — polled by `ActiveTokens.get_damage_multiplier()` inside `RuntimeToken_Damage.fire()`, after resistance, before finalising. Returns 1.0 by default. One modifier applied per token type — quantity is duration, not magnitude.

### Tick Timing

| Token | Trigger | Notes |
|-------|---------|-------|
| DoT (POISON, BURN, BLEED) | ON_TURN_START | One instance ticked and consumed at start of the affected actor's own turn |
| STUN | — | Consumed by `CombatFSM._enter_turn_start()` before AP gain; DoT ticks still fire first |
| Buff (EMPOWER) | ON_TURN_END | `skip_first_tick = true` — cast turn is free; 3 tokens = 3 boosted attacks |
| Debuff (WEAKEN) | ON_TURN_END | No skip needed — ticks at end of the *target's* turn, not the caster's |

### Mutual Cancellation

`RuntimeToken.opposes` — when set, `ActiveTokens.add_token()` removes one existing instance of the opposing type rather than stacking. EMPOWER ↔ WEAKEN: the two can never coexist on the same actor.

### Passive vs Reaction

Not every token that responds to combat is a "reaction." PRE/POST passes are for tokens that need a before/after window around the primary action. Everything else is passive state read inline.

| Token | Type | Resolution point |
|-------|------|-----------------|
| **EMPOWER / WEAKEN** | Passive | `RuntimeToken_Damage.fire()` — multiplier polled after resistance calc |
| **COVER / INTERCEPT** | Passive (future) | `RuntimeToken_Damage.fire()` — target redirect before damage calc |
| **BRACE / Shield** | Passive (future) | `RuntimeToken_Damage.fire()` — damage modifier during calc |
| **COUNTER** | POST reaction | ActionPipeline post-pass — retaliates after primary lands |
| **VIGIL** | POST reaction | ActionPipeline post-pass — heals damaged ally after primary resolves |
| **HAMEDO** | PRE reaction (future) | ActionPipeline pre-pass — may down attacker, cancel action |
| **PREMONITION** | PRE reaction (future) | ActionPipeline pre-pass — sets `context.negated = true` |
| **FOLLOW UP** | POST reaction (future) | ActionPipeline post-pass — fires after ally hits |

### ActiveTokens

`ActiveTokens` is a `Node` on every `CombatCharacter`. It owns the live token list and exposes:

```
add_token(token)              — adds token; handles mutual cancellation; emits token_added
remove_token(token)           — emits token_removed
tick_turn_start()             — fires + consumes one ON_TURN_START token per type
tick_turn_end()               — fires + consumes one ON_TURN_END token per type; respects skip_first_tick
consume_if_present(type)      — removes one token of type; returns bool (STUN check)
consume_all(type) -> int      — removes all of type; returns count (ENVENOM detonation)
has_token(type) -> bool       — presence check without consuming (ActionMenu preconditions)
collect_triggers(ctx, trig)   — one token per type whose check_trigger passes (reaction dispatch)
get_damage_multiplier()       — multiplies all non-1.0 passive modifiers, one per type
get_display_text()            — "POISON×3 EMPOWER×1" format for card UI
flush()                       — clears all tokens at end of combat
```

### Action Resolution Flow

```
CombatFSM._enter_action_execution()
  └── ActionPipeline.run(mnemonic, attacker, target, actors)
        ├── Create ActionContext
        ├── Emit action_announced → hold 0.5s for presentation
        ├── PRE-PASS: collect + fire PRE_EXECUTION tokens across all actors
        │     └── Each reaction fires with its own fresh ActionContext
        ├── VALIDATE: source alive? AP/MP sufficient? negated?
        ├── Spend AP/MP (only if validation passes)
        ├── SkillExecutor.execute(context) — primary action
        │     └── For each effect in mnemonic.effect_steps:
        │           ├── Check needs_previous_hit vs context.any_hit
        │           ├── Skill_Effect_Instant → duplicate token, fire(context), discard
        │           └── Skill_Effect_Grant   → duplicate token N times, add to target.tokens
        ├── Spend hp_cost_percent (if any)
        ├── Brief pause (0.4s) for damage numbers to settle
        ├── Check primary target downed
        ├── POST-PASS: collect + fire ON_DAMAGE_TAKEN / ON_ALLY_HIT tokens
        │     └── Announce reaction, 0.5s pause, fire with fresh ActionContext
        ├── Emit action_resolved(context)
        └── Emit pipeline_complete → FSM transitions to TURN_END
```

**Key rules:**
- Validation happens after pre-pass, before resource spend. Pre-reactions can down the attacker; if so, action is `cancelled` — no AP/MP spent.
- If a PRE reaction negates the action, action is `negated` — AP/MP **are** spent.
- Reactions fire with their own clean `ActionContext`. `trigger_context` points back to the primary context.
- Post-queue is built from the primary context only. Reaction attacks do not trigger further reactions.

### DoT Tick Formulas

Fixed per DoT type — not authored per instance:

```
POISON: (max_hp × 10% + max_mp × 10%) × resist_multiplier
BURN:   max_hp × 10% × resist_multiplier
BLEED:  max_hp × 10% × resist_multiplier
```

IMMUNE targets: tick resolves to 0 damage; token instance is still consumed.

### ActionContext — Execution Snapshot

Created by `ActionPipeline` before any effects resolve. Reactions get their own fresh `ActionContext` with `trigger_context` pointing back to the primary.

```
ActionContext
  ├── mnemonic, source, target             ← set by ActionPipeline
  ├── step_results: Array                  ← {hit, damage, is_crit} per effect step
  ├── tokens_applied: Array                ← persistent tokens added this execution
  ├── total_damage, any_hit, any_crit      ← rolling totals updated by record_step()
  ├── trigger_context: ActionContext       ← set on reaction contexts; points to primary action
  ├── negated: bool                        ← set by PRE reaction
  ├── cancelled: bool                      ← set by ActionPipeline when validation fails
  ├── pre_queue: Array                     ← RuntimeTokens collected during pre-pass
  └── post_queue: Array                    ← RuntimeTokens collected during post-pass
```

---

## Skill Data Layer

Skills are authored as `.tres` resources. All behaviour lives in token subclasses — effect classes are dispatch mechanisms only.

### MnemonicResource

One skill's complete definition:

```
MnemonicResource
  ├── mnemonic_name, rank, is_melee, merge_display
  ├── ap_cost, mp_cost, hp_cost_percent
  ├── requires_token_on_enemy: String     ← if set, ActionMenu greys skill unless an active enemy holds this token
  ├── targeting: TargetingData            ← shape (SINGLE/ALL/SELF) + filter (HAS_DOT, IS_DOWNED, etc.)
  └── effect_steps: Array[Skill_Effect_Base]
```

### Skill_Effect_Base Hierarchy

```
Skill_Effect_Base (Resource)
  ├── needs_previous_hit: bool   ← skip this step if the prior step missed
  ├── Skill_Effect_Instant       ← token: RuntimeToken — duplicate, set source/owner, call fire() immediately
  ├── Skill_Effect_Grant         ← token: RuntimeToken, amount: int — add N instances to target.tokens
  └── Skill_Effect_Remove        ← token_type: String — remove matching tokens (stub, not yet wired)
```

Effect classes carry no behaviour of their own. `Skill_Effect_Instant` fires the token immediately and discards it — used for damage, finishers, and instant heals. `Skill_Effect_Grant` installs persistent token instances into `ActiveTokens` — used for DoTs, buffs, debuffs, reactions, and ailments. The token's own `fire()` or `tick()` handles everything else.

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

**Open gaps:**
- `TargetingData.shape` SELF and SINGLE are wired. ALL (multi-target) is not yet consumed by `SkillExecutor`.
- Hardcoded `create_timer()` delays stand in for a `presentation_finished` signal — sufficient until presentation polish pass.
- TURN_START state does not yet tick DoT/HoT for ALL actors; it only ticks the active actor's tokens. Party HoT (VIGIL heals) relies on the POST-pass in ActionPipeline, not TurnStart.

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
