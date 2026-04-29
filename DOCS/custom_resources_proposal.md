# NEVERWORLD V2 — Custom Resources Proposal

> Design document. No code changes implied yet.
> Purpose: map where Godot custom Resources (`extends Resource`) are already used well, where they're underused, and where the biggest gains are.

---

## What We're Talking About

A Godot Resource is a data object that:
- Can be authored once in the editor and saved as a `.tres` file
- Can be serialized and loaded from disk with zero extra code (`ResourceSaver` / `ResourceLoader`)
- Can hold references to other Resources (enabling graph/tree structures)
- Can optionally carry methods — so a Resource can be a self-contained component, not just a bag of fields

The guiding split: **Nodes own behavior and scene tree presence. Resources own authored data.**

---

## What's Already Right

The codebase has good instincts. Don't change any of the following.

**Clean authored-data Resources:**
- `CharacterData → CombatData → PlayerData / EnemyData` — justified inheritance chain; each level adds genuinely distinct fields, no logic mixed in
- `GrowthTable` + `GrowthEntry` — correct pattern for per-level stat growth
- `CharacterSaveData` + `GlobalSaveData` — clean runtime state snapshot; already serializable for free
- `CombatConfig` + `EncounterPoolEntry` — weighted encounter composition as Resources; correct
- `ResistanceProfile` — data with one utility method (`get_state()`); that method belongs there, not elsewhere

**The save architecture is sound.** `GlobalSaveData` as a Resource root → `CharacterSaveData` per character, keyed by ID. This is idiomatic Godot and will serialize painlessly when save/load is implemented.

---

## Suggestions by Impact

### 1. Area / Zone — Already Designed Correctly

**Note:** A full design spec and implementation plan exist at `docs/superpowers/specs/2026-04-25-area-zone-architecture-design.md`. The architecture is partially implemented (Phases 0–5 done). This section documents the agreed design for reference only — no changes suggested.

**Area = Resource.** An `Area` is pure data: `area_name`, `entry_zone: PackedScene`, `world_map_position`, and eventually a zone connection graph. Areas don't get instanced into the scene tree. They exist for the world map layer to reason about regions and for GameManager to know which zone to load on area entry.

**Zone = Scene (node composition).** A Zone is a `PackedScene` with a fixed structure: `System` / `SpawnPoints` / `NPCs` / `Items` / `Triggers` / `Puzzles` / `Exploration` / `Combat`. Authored data (BGM stream, environment scene reference, encounter pool entries) lives as exports on child nodes within the zone scene — not in a consolidated Resource. This is intentional: the nodes own lifecycle behavior (`play()`, `stop()`, `enter()`, `exit()`), not just data.

**Shared data across zones in an area** is handled by referencing the same `.tres` files — e.g., multiple forest zones all point to the same `forest_environment.tres`. DRY through Resource references, not through node ownership.

**What this means for authoring a new zone:** duplicate `zone_template.tscn`, populate the child nodes' exports, add spawn points, place zone exits. No new scripts needed. The template structure is the interface.

The `ZoneConfig` Resource consolidation idea (raised earlier in design discussion) conflicts with this decision and is not recommended. The node composition approach was chosen deliberately and the spec explains why.

---

### 2. Mnemonic Base + Effect Steps — The Biggest Missing Piece

**Current state:** Mnemonics are referenced everywhere (`CharacterSaveData.equipped_mnemonic_ids`) but no Resource for them exists yet. The entire skill system has no authored data foundation.

**What to do:** Two Resources, one clear rule.

**`MnemonicData`** (the mnemonic itself — passive data):
- AP cost, HP% cost, MP cost
- `IsMelee` flag, `TrueStrike` flag, `MergeEffectDisplay` flag
- `effect_steps: Array[SkillEffect]` — ordered list of effect step Resources

**`SkillEffect`** (base class — active component):
- Each effect subclass (`SkillEffect_Damage`, `SkillEffect_DoT`, `SkillEffect_Buff`, etc.) holds its authored fields *and* a `resolve(context, source, target)` method
- The execution pipeline iterates `effect_steps` and calls `resolve()` on each — that's the entire pipeline, it never grows

The critical design choice here is **active Resources**: logic lives in the effect, not in an external pipeline. Adding a new effect type means creating one new Resource subclass — nothing else changes anywhere.

**Effect subclasses to author (from the GDD vocabulary):**

| Subclass | Key fields |
|---|---|
| `SkillEffect_Damage` | `power`, `damage_type`, `requires_previous_hit` |
| `SkillEffect_Healing` | `heal_power`, `scaling_stat` |
| `SkillEffect_Buff` | `buff_type`, `stackable`, `use_hit_count` |
| `SkillEffect_Debuff` | `debuff_type` |
| `SkillEffect_DoT` | `dot_type`, `charges`, `requires_previous_hit` |
| `SkillEffect_HoT` | `hot_type`, `charges` |
| `SkillEffect_Ailment` | `ailment_type`, `hit_chance_tier` |
| `SkillEffect_Etc` | `token_type` (Stance / Trigger / Mark) |
| `SkillEffect_ModifyAP` | `amount` (positive = restore, negative = drain) |
| `SkillEffect_Cleanse` | `target_types` (DoTs / debuffs / ailments) |
| `SkillEffect_Convert` | `from_type`, `to_type` |
| `SkillEffect_Transfer` | `token_type`, `direction` |

**Item effects** (`ItemEffect_Damage`, `ItemEffect_RestoreHP`, `ItemEffect_RestoreMP`) are the same pattern but simpler — fixed values, no stat scaling, always resolve. They share the execution pipeline.

**The gain:**
- The entire skill vocabulary is authored in the editor as `.tres` files — readable, inspectable, no code needed to create a new skill
- The execution pipeline is trivially simple and never grows
- Items and mnemonics share the same pipeline — one system, not two

---

### 3. Mnemonic Progression Graph — Author the Chain, Not Just the Base

**Current state:** The GDD describes a branching upgrade graph (Uskrav → Uskrav II → Uskrav III → Sporlaus or Tvingar). No data structure exists for this yet.

**What to do:** A `ChainNode` Resource that references its children:

**`ChainNode`** (each rank or branch point in the upgrade graph):
- `power`, `ap_cost`, `hp_cost_percent`, `mp_cost`, `special_notes`
- `resonance_cost` (how much RESONANCE to unlock this node)
- `next_ranks: Array[ChainNode]` — one entry for linear progression, two for a branch point

A branch point is just a `ChainNode` with two children. Both paths are authored; the save system records which branch was taken (and marks the other permanently closed). The graph is a tree of `.tres` files you can inspect and edit in the Godot editor directly.

Every `MnemonicData` has a `chain_root: ChainNode` field pointing to the first node in its chain.

**The gain:**
- The entire Uskrav chain — trunk, branch point, both paths — is authored once in the editor, never touched in code
- Inspecting a mnemonic's progression graph at runtime means traversing a Resource tree — no parsing, no custom format
- The save system only needs to store: current node path (which branch was taken) — the authored graph provides everything else

---

### 4. Token Blueprints — Separate the Recipe from the Cooked Thing

**Current state:** `ActiveTokens` is a stub node. No token blueprint structure exists.

**The distinction the GDD makes is critical:** a token blueprint is authored data (static, created once). A live token is a runtime object (created during combat, tracks charges and owner).

**What to do:**

**`TokenBlueprint`** (Resource — the authored recipe):
- `trigger: TokenTrigger` (enum: Instant, OnTurnStart, OnDamageTaken, OnAllyHit, OnNextPhysHit)
- `payload: TokenPayload` (Resource subclass — see below)
- `charges: int`

**`TokenPayload`** (Resource base class with behavior):
- Subclasses: `DamagePayload`, `HealPayload`, `BuffPayload`, `DebuffPayload`, `ReduceIncomingPayload`
- Each has a `fire(owner, source, context)` method
- The same `DamagePayload` works whether it fires instantly (sword slash), on a timer (BURN tick), or reactively (Counter Strike) — the trigger governs *when*, the payload governs *what*

**Live token** (RefCounted — the runtime instance):
- Holds a reference to its `TokenBlueprint`
- Tracks `owner`, `source`, `remaining_charges`
- Created by the execution pipeline, attached to a combatant, handles its own lifecycle

**The gain:**
- Every token type in the game is a `TokenBlueprint.tres` file, authored once in the editor
- The execution pipeline stamps out live tokens from blueprints — it doesn't need to know what kind of token it's creating
- Tokens can be transferred, cleansed, and converted because they're discrete objects, not counters

---

### 5. Gear Resources — When the Time Comes

**Current state:** Gear is referenced by ID strings in `CharacterSaveData` but no Resource subclasses exist. `LootTable` and `AIProfile` are empty stubs. `EquipmentType` provides flags.

**This is the right state to be in right now** — don't build gear Resources until the skill and combat pipeline exists, because gear modifies stats and interacts with the combat system. Building the data structure before the system is a trap.

**When you do build it:**

**`GearData`** (base Resource):
- `id: String`, `display_name: String`, `equipment_type: EquipmentType.Flags`
- Flat stat modifiers (same fields as `GrowthEntry` — consider sharing or mirroring)
- Flat resistance modifiers (same fields as `ResistanceProfile`)

**`WeaponData`** extends `GearData` — adds damage type for its basic attack  
**`ArmorData`** extends `GearData` — adds weight class  
**`AccessoryData`** extends `GearData` — no additional required fields  
**`ConsumableData`** extends `GearData` — adds `effects: Array[ItemEffect]` (mirrors mnemonic structure)

**`LootEntry`** (Resource — pair it with `LootTable`):
- `item_id: String`, `weight: int`

**`GambitRule`** (Resource — enemy scripted AI):
- `condition: GambitCondition` (enum or Resource describing the check)
- `skill_id: String` (which mnemonic the enemy uses when condition matches)

**The gain:** Enemy authoring becomes entirely editor-driven — stat block, resistance profile, gambit rules, loot table, all in one `.tres` file per enemy type. Adding an enemy = duplicating a `.tres`, no code.

---

### 6. Stat Computation — The Missing Utility

**Current state:** No code exists that answers "what are this character's effective stats right now?" This is needed at combat entry.

**This is not a Resource problem** — it's a missing function. But it interacts with Resources directly.

At combat start, effective stats = base stats (`CombatData`) + per-level growth (`GrowthTable`, summed to current level) + choice bonuses (`CharacterSaveData.choice_bonuses`) + gear flat modifiers (equipped `GearData`).

**What to do:** A single static utility function (or a thin `StatsComponent` node called once at combat entry) that takes `PlayerData` + `CharacterSaveData` + equipped gear and returns a plain Dictionary of resolved stats. That dictionary is what combat works with for the whole encounter.

**The gain:** Combat never reads Resources directly mid-fight — it works from the compiled snapshot. Stats are always consistent within an encounter.

---

## What Should NOT Be a Resource

| Concept | Why not |
|---|---|
| Logic FSM states | These are behavior nodes, not data |
| `CombatCalculator` | Pure utility with static methods — no state, no serialization needed |
| Resolution context | Ephemeral per-skill scratch pad — a plain `Dictionary` or simple object is correct |
| CT values | Per-actor runtime floats — live on the actor node |
| `StepCounter` | Has behavior (tick, threshold signal) — stays a Node, reads zone config data |

---

## Priority Summary

| Priority | Item | Gain | Effort |
|---|---|---|---|
| — | Area / Zone architecture | Already designed and partially implemented — no action needed | — |
| 1 | `MnemonicData` + `SkillEffect` hierarchy | Core gameplay loop becomes authorable | Medium — many subclasses, clear pattern |
| 2 | `ChainNode` progression graph | Skill upgrades authored in editor, free serialization | Medium — graph structure, authoring |
| 3 | `TokenBlueprint` + `TokenPayload` | Combat token system has clean separation | Medium — needs combat pipeline to be useful |
| 4 | `GearData` subclasses + `GambitRule` | Enemy authoring fully editor-driven | Low-Medium — do after combat pipeline |
| 5 | Stat computation utility | Combat has consistent stat snapshots | Low — one function, clear inputs |

---

## The Pattern in One Sentence

**Author data as `.tres` files. Put behavior in Resources only when the behavior belongs to the data itself (effect steps, token payloads). Everything else is a Node.**
