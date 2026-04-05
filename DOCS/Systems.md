# NEVERWORLD — Game Design Document V2

> This document is the design source of truth for NEVERWORLD V2.
> This is a living document. Stubs and TODOs are intentional — fill them as design crystallizes.

---

## DESIGN PILLARS

1. **Readability** — Player can intuit outcomes without spreadsheets.
2. **Build Identity** — Same character, different loadout, different playstyle.
3. **Ripples** — Everything is a discrete, visible, manipulable event.
4. **Shared Investment** — Party-wide resource decisions, not just individual progression.
5. **Preparation Matters** — Enemy knowledge is rewarded.
6. **Exploration as Infrastructure** — Traversal serves story and combat.
7. **Scope Honesty** — Solo dev reality informs every design choice.

---

## SKILL SYSTEM

### Core Principle: Mnemonics

Skills are **Mnemonics** — physical objects that encode technique, combat knowledge, and concentrated belief. You don't learn a skill, you *run* a mnemonic. You don't train an ability, you *carry* one.

In NEVERWORLD's post-singularity setting, the boundary between information and matter has eroded. The unconscious layer — where emotion, belief, and hyperstition accumulate — seeps into physical reality wherever the signal is strong enough. Mnemonics are nodes where that layer punched through and crystallized. Some predate living memory. Nobody knows who encoded the first ones. They exist, they work, and that's enough.

This is hyperstition made literal: a technique that became real because enough people believed it, used it, and passed it on. The mnemonic works because it has always worked. Belief and matter are the same thing here.

**Mechanically:** Mnemonics are discrete, ownable items — not entries in a character-locked tree, not stat unlocks, not class features. Each instance is its own object. Skugge's copy and Vargi's copy are two separate things. They grow, get reforged, and can be lost. Think equipment, not abilities.

Mnemonics are acquirable party-wide — any character can carry any mnemonic. New instances can be scribed from the Compendium for RESONANCE as many times as you can afford. What differentiates characters is not an exclusive list but which mnemonics they're drawn toward, invest in, and build around.

> **TODO:** Debate whether to encourage character-mnemonic affinity mechanically. Example: a dagger mnemonic used by Skugge ranks up faster than the same mnemonic in Vargi's hands. Rewards thematic coherence without hard gating. Risk: creates invisible pressure that feels punishing if the player doesn't know about it.

---

### Skill Construction

A mnemonic is a **data resource** — a `.tres` file, not a script. It holds cost metadata and an ordered list of **effect steps.** There is no skill logic in the mnemonic itself. Logic lives in the effect components.

```
Mnemonic (SkillClass_Base)
├── APCost, HPCostPercent, MPCost
├── IsMelee, TrueStrike
└── EffectSteps[]
      ├── Skill_Effect_Damage   (step 1 — hit the target)
      └── Skill_Effect_DoT      (step 2 — apply poison if step 1 hit)
```

Each effect step is its own resource — a self-contained component that knows what it does, what stats it reads, and what token it creates. The execution pipeline iterates the list and resolves each step in order. The mnemonic is passive data. The effects are the behavior.

#### Effect Vocabulary

**Mnemonic effects** — stat-scaling, full pipeline:

| Effect | What it does |
|--------|-------------|
| `Skill_Effect_Damage` | Deal damage. Reads Power + AtkStat vs DefStat. Full pipeline (resist, buff/debuff, crit). |
| `Skill_Effect_Healing` | Restore HP. Reads HealPower × ScalingStat. No resist or crit. |
| `Skill_Effect_Buff` | Apply a buff token to a target. Stackable flag for effects like MOMENTUM. |
| `Skill_Effect_Debuff` | Apply a debuff token to the target. |
| `Skill_Effect_DoT` | Apply a DoT token (BURN, POISON, BLEED). Ticks on target's TurnStart. |
| `Skill_Effect_HoT` | Apply a HoT token (REGEN, VIVIFY). Ticks on recipient's TurnStart. |
| `Skill_Effect_Ailment` | Apply a CC ailment (FREEZE, WINDED, PETRIFY). Chance-gated, resistance-blocked. |
| `Skill_Effect_Etc` | Apply a special token — Stance, Trigger, or Mark. Type set per effect instance. |
| `Skill_Effect_ModifyAP` | Drain or restore AP. Positive = restore, negative = drain. |
| `Skill_Effect_Cleanse` | Remove active tokens from the target by type (DoTs, debuffs, ailments). |
| `Skill_Effect_Convert` | Convert one active token type to another on the target. |
| `Skill_Effect_Transfer` | Move tokens from one combatant to another. |

**Item effects** — fixed values, no stat scaling, no crit, always resolve:

| Effect | What it does |
|--------|-------------|
| `Item_Effect_Damage` | Fixed damage. Bypasses stat scaling entirely. |
| `Item_Effect_RestoreHP` | Fixed HP restore. |
| `Item_Effect_RestoreMP` | Fixed MP restore. |

Items and mnemonics share the same execution pipeline — the distinction is in the subclass, not the system.

#### Damage Formula

Each `Skill_Effect_Damage` step has a hand-authored integer **Power** value. Damage resolves as:

```
damage = Power × AtkStat / (DefStat + 10) × Random(0.85, 1.0)
```

- **Power** — authored per effect. Readable baseline: Power 35 ≈ 35 damage against an equally-matched enemy.
- **AtkStat** — attacker's relevant stat: Phys.Atk for physical, Magic.Atk for magical.
- **DefStat** — defender's relevant stat: Phys.Def or Magic.Def.
- **+10 offset** — softens defense scaling at low values, prevents division by near-zero.
- **Random(0.85–1.0)** — variance roll. Same spread as Pokémon.
- Result rounded to int; minimum 1.

No level multiplier — AtkStat already reflects level progression through dual-axis stat growth. A separate level term would double-amplify it.

The base damage then feeds the full combat pipeline: immune check → resist multiplier → buff/debuff multipliers → elemental vulnerability → crit → floor 1.

#### Conditional Chaining

A mnemonic's effect list is an ordered sequence. Each step can read what the previous step did via a shared **resolution context** — a scratch pad tracking: did the last step hit, was it a crit, how many targets were hit. This enables conditional effects:

> **Poison Jab** = `[Skill_Effect_Damage, Skill_Effect_DoT(RequiresPreviousHit=true)]`
> The DoT only applies if the damage landed. Miss the hit, no poison.

The resolution context is ephemeral — created at skill execution, discarded when the last step finishes. It is not token state.

#### Merged vs Sequential Display

Multi-step skills have a `MergeEffectDisplay` flag that controls how their effects are presented:

- **Sequential** — each step rolls hit independently and shows its own floating number. A miss on step 1 doesn't prevent step 2 from landing. Each step feels like a separate event.
- **Merged** — step 0's hit roll gates the entire skill. All damage steps accumulate pre-crit into one total, one crit roll on the unified value, one floating number. Feels like a single powerful strike.

This is a per-skill authoring decision, not a per-effect one. A two-hit skill that should feel like two distinct attacks is Sequential. A skill with a damage component and a followup that only makes sense if the hit landed is Merged.

---

### Skill Ranks

Skills have ranks. Higher rank means higher Power, better AP efficiency, occasionally new mechanics — not arbitrary resistance flags. A low-rank skill against a high-defense enemy does pathetic damage. The numbers tell the story. No "RESIST" labels needed.

This is the core pressure to engage with the RESONANCE system. Ignoring skill investment doesn't lock you out — it just makes you ineffective in a way that's immediately legible. Low Power can't compensate for a widening stat gap as the game progresses.

---

### Mnemonic Progression

Mnemonics have two distinct states: **BASE** and **UPGRADED/MUTATED.**

**BASE** is the entry point — the skill as it exists before investment. Usually more reserved mechanically.

**UPGRADED/MUTATED** is only reachable by climbing the chain. Most are earned through RESONANCE investment — the mnemonic is reforged, not replaced.

The upgrade path is **branching, not linear.** RESONANCE investment upgrades a skill vertically (Uskrav → Uskrav II → Uskrav III). At certain thresholds, the skill reaches a **branch point** — a permanent, no-take-backs reforge decision. Pick one branch; the other is gone from that instance. Branches can themselves become new trunks.

**Vertical upgrades** — same skill, improved. **Branch points** — permanent identity mutation. Choose once.

#### Chain Design Principles

**Depth is a design signal, not a quality signal.** A 1-node chain means the skill is complete at base. A 5-node branching chain means the designer wants the player to commit and choose. Neither is better — depth reflects the skill's role in the game.

**Vertical ranks: same identity, better numbers.** The primary lever is Power. Other changes (cost shifts, secondary effects) are optional — only used when they reinforce something specific, not as a default.

**Branch points: identity mutations, not upgrades.** Both paths should feel genuinely different. Tools for making branches distinct:
- **Power trade-off** — one branch takes a Power cut in exchange for a mechanic
- **Cost personality** — AP or HP% changes that reinforce the branch's identity
- **Conditional mechanics** — the payoff requires setup (DoT on target, ally low HP, etc.)
- **Reliability vs ceiling** — guaranteed hit/effect vs higher raw output with risk

**Costs are tools, not progression rules.** AP and HP% costs don't automatically decrease as a skill ranks up. They change only when that change means something.

#### Worked Example: Uskrav Chain

Skugge's starting dagger skill. An elaborate chain — not every mnemonic will look like this.

```
Uskrav
  └── Uskrav II
        └── Uskrav III
              ├── Sporlaus   (reliability branch)
              └── Tvingar
                    └── Tvingar II
```

| Node | Power | AP | HP% | Special |
|------|-------|----|-----|---------|
| Uskrav | 30 | 2 | 15% | — |
| Uskrav II | 45 | 2 | 15% | — |
| Uskrav III | 70 | 2 | 15% | — |
| Sporlaus | 55 | 1 | 5% | True Strike (never misses) |
| Tvingar | 55 | 2 | 25% | Guaranteed crit if target has DoT |
| Tvingar II | 75 | 2 | 25% | Guaranteed crit if target has DoT |

**Trunk (I→II→III):** same cost, increasing Power. Rewards RESONANCE investment with raw output.

**Sporlaus:** power cut in exchange for reliability — 1 AP, 5% HP, never misses. Low-maintenance consistent pressure.

**Tvingar:** same power cut, higher HP cost (25%), guaranteed crit against DoT targets. Miss the setup and you've paid 25% HP for a weak hit. Land it and effective Power is 82.5 — above the trunk.

**Tvingar II:** recovers the power gap (75 vs trunk's 70) while keeping the condition and cost. Rewards full commitment to the branch.

The branch decision is reliability vs ceiling. Sporlaus players don't build around DoT. Tvingar players commit to setup — and when it lands, they hit harder than anything else in the chain.

---

### Acquisition

#### The Skill Compendium

The Compendium is the party's skill catalogue — a grimoire with blank pages. Known skills appear by name and can be scribed (spend RESONANCE to create an instance). Unknown skills appear as **???** — slots you know exist but can't access yet.

The catalogue is not a spreadsheet available from the start. You build it by engaging with the world. Knowing what's behind a ??? before anyone else does is itself a form of progress.

#### REFRACTION

A character can learn a skill directly from an enemy by witnessing it while under a DEFENSIVE stance and surviving combat. The witnessed skill is added to the Compendium as a known template — no longer ???, available for purchase.

REFRACTION is the *discovery* vector — it introduces skills into the Compendium that couldn't be predicted or purchased. Engaging with the world fills the grimoire.

> Acquisition condition details (defend stance required? HP threshold? specific setup?) — TBD.

#### Loot

Skills can drop from enemies or appear in chests as physical items. Picking one up adds its template to the Compendium and makes the skill available for scribing.

---

## RESOURCE SYSTEM

### AP — Action Economy (combat only)
Per-character. Gained at the start of your own turn (+1, modifiable by gear/mnemonics). Carries over between turns — unspent AP accumulates and creates tempo pressure. Spent to play mnemonics. Resets between encounters.

### HP — Physical Cost + Survival
Some mnemonics cost HP to run (physical techniques that damage the user). Also the primary survival resource — hit zero and the character goes down, their mnemonics go offline for the rest of the encounter. Persists across encounters. Restored at rest points and via healing mnemonics.

### MP — Magical Cost + Dungeon Attrition
Some mnemonics cost MP to run (magical/encoded techniques that draw on the signal). MP is the dungeon attrition layer — it drains across encounters and isn't restored by winning fights. A boss approached with empty MP means your signal-hungry mnemonics are offline or running degraded. Restored at rest points.

**The dungeon loop:** AP resets each fight. HP and MP persist and drain. Rest points restore both. Arrive at the boss in the right shape — that's the puzzle.

---


## CHARACTERS

| Character | Stat Focus | Gear Access |
|-----------|------------|-------------|
| **Skugge** | High PULSE, Dodge, Phys.Atk | Daggers/swords, light armor |
| **Vargi** | High Phys.Atk, HP | Axes/maces, medium/heavy armor, shields |
| **Milis** | High Magic.Atk, MP | Staves, light armor |

### Character Identity

Identity is **implied, not enforced.** No class gates, no mnemonic eligibility rules. Any character can equip any mnemonic. What differentiates them is effectiveness.

**Stats** — the primary signal. Each character has different stat growth, making them naturally better at certain mnemonics. Vargi healing with a magic mnemonic works; his Magic stat makes it weak. The numbers communicate the misfit without blocking it.

Stat growth has two components:
- **Natural growth** — hand-authored per-level increases, different per character.
- **Choice growth** — on level-up, pick one stat from three randomly generated options. Small nudges over time. Cumulative choices can bend a character slightly off their default lane.

**Gear** — weapon type and armor class vary per character, reinforcing their stat identity structurally.

**Mnemonic slots** — 4 per character, universal. No slot typing. The constraint is count: 4 mnemonics in the dungeon, choose carefully.

The slot system is intentionally minimal — expandable later (gear-contributed slots, slot counts per item, typed slots) without changing the core loop.

---

## COMBAT — FSM ARCHITECTURE

Combat is driven by **two FSMs running in parallel** — one for logic, one for presentation. They communicate exclusively through the event bus. The logic FSM never touches UI. The UI FSM never touches game state.

**Why two:** combat logic (turn order, damage resolution, resource mutation) and combat presentation (animations, banners, floating numbers, bar updates) change for different reasons. Coupling them into the same state machine is the primary source of complexity.

**Coordination:** the logic FSM pauses at defined checkpoints and waits for a `PresentationReady` signal from the UI FSM before continuing. The logic side doesn't know or care what was shown — only that the UI is done.

**State creation rule:** separate states when behavior differs. Same state with configuration when only data differs.

**No god-managers.** Combat has distinct concerns — encounter setup, turn orchestration, actor spawning, cursor management, post-combat flow. Each belongs in its own node or scene. A single autoload that handles all of these becomes unmaintainable. Split by responsibility: if you can name the concern, it's probably its own node.

### Logic FSM States

| State | Responsibility |
|---|---|
| `CombatStart` | Call `EnterBattle` on all actors, emit `CombatStarted` |
| `TurnStart` | Tick CT for all non-downed actors, find highest-priority ready actor, emit `TurnStarted` |
| `ActionSelect` | Party: await `ActionConfirmed` from player input. Enemy: run gambit evaluator |
| `ActionExecution` | Resolve skill — hit/miss, crit, all effect steps via `CombatCalculator`, emit damage/miss/crit events |
| `ReactionScan` | Drain `ReactionQueue` in priority order; each reaction re-enters `ActionExecution` |
| `TurnEnd` | Consume CT, emit `TurnEnded`, check win/loss condition |
| `CombatEnd` | Emit `CombatEnded`, hand off to post-combat flow (XP, loot, exit) |

### UI FSM States

| State | Responsibility |
|---|---|
| `CombatStart` | Fade in, present opening, spawn actor visuals |
| `TurnStart` | Highlight active actor, slide in command menu |
| `ActionSelect` | Show command menu, skill list, tooltips |
| `Targeting` | Cursors on valid targets, input cycling — covers skills and items |
| `TacticsInspect` | Cursors on all actors, inspect panel on confirm |
| `ActionExecution` | Skill banner, animations, floating numbers, bar updates |
| `ReactionScan` | Present reaction firing |
| `TurnEnd` | Bar updates, downed presentation |
| `CombatEnd` | Victory/defeat screen, XP flow |

---

## COMBAT — TURN STRUCTURE

### Party Size
**3 characters.** Final. 3 × loadout = the full toolkit for every encounter.

**Enemy count per encounter:** 1–6.

### CT / PULSE Turn System

Turn order is governed by **CT (Charge Time)** and the **PULSE** stat.

- Each actor has a CT value (float, 0.0–1.0+).
- After each action, every non-downed actor accumulates CT equal to `PULSE / 100` per tick.
- The first actor to reach CT ≥ 1.0 takes their turn.
- Acting subtracts 1.0 from CT — overflow is preserved, giving faster actors a head start on their next turn.
- **Tiebreaker:** higher PULSE acts first.
- PULSE is displayed as a plain integer (e.g., 10); the CT rate is derived at runtime.
- Downed actors do not tick CT and cannot act.

This means higher-PULSE characters act noticeably more often over the course of a fight, not merely sooner in the first round. Tempo is a real stat.

### Combat Encounter Flow

Combat takes place in a **dedicated battle scene** — a separate environment loaded on encounter trigger, not the overworld itself. The overworld freezes, the battle scene fades in, the fight resolves, and the player returns to the exact point they left. The background of the battle scene reflects the zone where the encounter was triggered — forest, ruin interior, cave, coastal cliff, etc.

Encounters are **random** — triggered stochastically as the player moves through encounter-enabled zones. Each zone has a configurable step counter and encounter rate. There are no visible overworld enemies to chase or avoid.

**Trigger flow:**
1. Player moves through an encounter-enabled zone; step counter ticks.
2. Counter threshold reached → encounter check passes.
3. Screen fades out.
4. Battle scene loads with the appropriate background; actors are placed at authored spawn positions.
5. Screen fades in — combat begins.

**Exit flow:**
1. All enemies downed → post-combat UI (XP, loot).
2. Player confirms.
3. Fade out → battle scene unloads, overworld resumes at the player's position.
4. Fade in → exploration resumes.

**Party wipe:** Game Over → return to last save. No permadeath.

**Zone configuration per area:**
- Encounter rate (steps between checks, or probability per step)
- Enemy pool (which enemy groups can spawn)
- Background asset reference

### Stat Block

**Resources** (% growth per level, % allocation):

| Stat | Purpose |
|------|---------|
| HP | Survival. Some skills cost % of MaxHP to use. Persists across encounters. |
| MP | Magical attrition. Costs flat MP. Persists across encounters. Restored at rest points. |

**Offensive:**

| Stat | Purpose |
|------|---------|
| Phys.Atk | Physical damage output |
| Magic.Atk | Magical damage output |

**Defensive:**

| Stat | Purpose |
|------|---------|
| Phys.Def | Physical damage reduction |
| Magic.Def | Magical damage reduction |

**Utility:**

| Stat | Purpose |
|------|---------|
| PULSE | CT accumulation rate — governs turn frequency |
| HIT | Physical accuracy |
| DODGE | Physical evasion |
| WARD | Magical evasion |

### Hit / Miss Formula

```
hitChance = clamp( (attacker.HIT × ChanceTier%) / defender.DODGE, 5%, 95% )
```

For magical skills, WARD replaces DODGE. 5% floor means nothing is impossible; 95% ceiling means nothing is guaranteed.

### Crit System

- Baseline 5% crit chance on all offensive skills (authored per skill, not global).
- Crit = 2× damage.
- KEEN buff (stackable=false, persists until consumed) guarantees crit on the next physical hit.

### Resistance & Damage Types

**Physical damage types:** Slash, Pierce, Blunt.
**Elemental damage types:** Fire, Water, Air, Nature, Stone, Feral.

Resistance is a single axis per damage type, authored per enemy:

| Value | Meaning |
|-------|---------|
| −100 | Full weakness — 2× damage taken |
| 0 | Neutral — 1× damage taken |
| 100+ | Immune — 0 damage taken |

Damage, DoT tick damage, and ailment landing chances each interact with resistance differently:

**Damage** — multiplied by `clamp(1 − resistStat / 100, 0.0, 2.0)`. At 100+ the immune check fires first and returns 0 before the multiplier is applied. Negative resistance (weakness) pushes the multiplier above 1.0.

**DoT tick damage** — same formula, applied per tick. A BURN on a fire-resistant enemy deals reduced damage each tick. Full fire immunity = 0 tick damage per tick. Resistance never stops a DoT from *landing* — only from *hurting*. The DoT token is still applied; the player sees it ticking for small or zero numbers.

**Ailment landing chance** — different formula:

```
landChance = clamp( ChanceTier% × (1 − resistStat / 100), 5%, 95% )
```

Resistance reduces the chance the ailment lands, not the effect itself. A 80% ChanceTier ailment against an enemy with 50 resistance: `80% × 0.5 = 40%`. Two hard limits apply: **5% floor** — nothing is ever fully immune to ailments, even capped resistance leaves a residual chance. **95% ceiling** — nothing is ever guaranteed to land.

The distinction matters in play: a fire-immune enemy takes zero BURN tick damage, but can still be FROZEN. Resistances are personality, not a total shutout.

### AP Economy

- All actors start combat with 3 AP.
- Each actor gains +1 AP at the start of their turn.
- AP carries over between turns (unspent AP accumulates — tempo pressure).
- AP cap: 10, all actors. Not a per-character stat.
- AP resets between encounters.
- Enemies pay AP costs too. Every enemy has a 1–2 AP fallback skill so AP drain can't cause a permanent stall.

| AP Cost | Skill Class |
|---------|-------------|
| 1–2 | Basic attacks, weak skills, items |
| 3–4 | Core bread-and-butter skills |
| 5–6 | Strong skills |
| 7–9 | Powerful fight-changers |
| 10–12 | Ultimate abilities — boss charge-up attacks live here |

### Skill Costs

Physical skills (weapon/physical mnemonics) cost **HP%** + AP.
Magical skills (elemental mnemonics) cost **flat MP** + AP.

| Tier | HP% Cost | MP Cost |
|------|----------|---------|
| Minor/Weak | 5% | 4–8 |
| Light/Solid | 10% | 12–20 |
| Heavy | 15% | 25–35 |
| Severe | 20% | 40+ |

### Death

- 0 HP = **Downed.** Cannot act. Revivable mid-combat.
- All party members downed = **Game Over.** Return to last save.
- No permadeath.

---

## COMBAT — RIPPLE FRAMEWORK

The core combat hook: **ripple manipulation.** Stack them, trigger them, strip them, combo them. Combat is reading and reacting to visible board state.

### Six Ripple Types

| Type | Player Reads As | Behavior |
|------|-----------------|----------|
| **AILMENT** | "I'm being hurt/disabled" | Ticks or expires; resistance-gated; tiered intensity |
| **BUFF** | "I'm stronger" | Duration-based; beneficial; always applies |
| **DEBUFF** | "They're weaker" | Duration-based; harmful; always applies if skill hits |
| **STANCE** | "I'm in a mode" | Persists until replaced/cancelled; multi-charge token |
| **TRIGGER** | "Something fires IF..." | Consumes when condition met; single-charge token |
| **MARK** | "This target is special" | Enables or empowers follow-up skills |

### Token Architecture

Every combat effect — from a basic sword slash to a three-turn BURN to a reactive counter stance — is a **token.** Tokens are self-resolving entities. They are created from a blueprint (the skill's authored data), attached to a target, and they handle their own lifecycle from there. The combat system doesn't need to know what kind of token it's dealing with — it just creates them and lets them run.

A token has five properties:

- **Owner** — the character carrying this token (who it's attached to)
- **Source** — the character who created it (matters for damage scaling)
- **Trigger** — when this token fires (Instant, OnTurnStart, OnDamageTaken, etc.)
- **Payload** — what it does when it fires (deal damage, heal, buff a stat, reduce incoming damage)
- **Charges** — how many times it fires before expiring

**The trigger determines the token's lifetime.** This is the core insight. An instant damage skill and a three-turn BURN are the same architecture — they differ only in trigger and charge count:

| Effect | Trigger | Charges | What Happens |
|--------|---------|---------|-------------|
| Sword slash | Instant | 1 | Created, fires immediately, expires |
| BURN (3 turns) | OnTurnStart | 3 | Ticks at the start of the owner's turn, −1 charge per tick |
| EMPOWER (2 turns) | OnTurnStart | 2 | Buffs a stat while active, ticks down each turn |
| Counter Strike | OnDamageTaken | 1 | Waits. When owner is hit, fires its payload (a damage effect), then expires |
| Vigil | OnAllyHit | 3 | Waits. When any ally takes damage, heals that ally. 3 charges = 3 reactions |
| Brace | OnDamageTaken | 1 | Reduces incoming damage by 40% on the next hit, then expires |
| KEEN | OnNextPhysHit | 1 | Guarantees a crit on the next physical hit, consumed on use |

**Charges = duration for ticking effects.** 3 charges on a DoT means 3 ticks — 3 turns. 3 charges on a reactive stance means 3 reactions before it expires. The number always means the same thing: how many times this token fires.

**Tokens are objects, not counters.** A BURN token is a discrete thing attached to a character. It can be transferred between combatants by a transfer skill. It can be cleansed. It ticks independently. Two BURN tokens on the same target tick separately.

**Composition:** the trigger and the payload are independent. A `DamagePayload` is the same component whether it fires instantly (sword slash), on a timer (BURN tick), or reactively (Counter Strike). A `HealPayload` is the same whether it fires instantly (Flash Heal) or reactively (Vigil). New token types = new trigger + existing payload. The resolution logic is written once per payload type.

**The execution state is an orchestrator, not a resolver.** It reads the skill's effect list, stamps out tokens from each blueprint, attaches them to the appropriate targets, and steps back. The tokens resolve themselves. The calculator is a utility that payload components call when they need math — it doesn't drive the flow.

**Multi-step skills and conditional chaining:** A mnemonic's effect list is an ordered sequence of steps. Each step can read what the previous step did via a shared scratch pad (resolution context). This enables conditional effects — Poison Jab is two steps: (1) deal Pierce damage, (2) apply 3 Poison tokens *if step 1 hit*. The DoT step has `RequiresPreviousHit = true` — if the damage missed, no poison. The scratch pad tracks: did the last step hit, was it a crit, how many targets were hit. This is internal to a single skill use and discarded afterward — it is not token state.

**Generator / Transfer / Detonator pattern:** Skills are designed as combo pieces. Every skill must have standalone value — combo payoff is the ceiling, not the floor. Full combo lines unlock gradually across progression (generator arrives before detonator in the unlock order).

### Status Effects Reference

**Elemental CC Ailments** (apply-chance gated, resistance blocks landing):

| Ailment | Effect |
|---------|--------|
| FREEZE (Water) | Action loss / speed debuff |
| WINDED (Air) | AP reduction |
| PETRIFY (Stone) | Skip turn(s) |

**Elemental DoTs** (always land if skill hits; resistance scales tick damage):

| DoT | Tag | Tick Formula | Passive Effect |
|-----|-----|-------------|----------------|
| BURN | Fire | MaxHP × 10% × resistMult | +fire damage taken while active |
| POISON | Nature | MaxHP × 10% + MaxMP × 10% × resistMult | — |
| BLEED | Feral | MaxHP × 10% × resistMult | Healing reduction while active |

`resistMult = clamp(1 − resistStat / 100, 0.0, 2.0)`

**Special stackable buffs:**
- **MOMENTUM** — +25% Phys.Atk per stack (physical only). Stacks consumed on next physical hit. Granted per enemy hit by CrimsonRhythm / BloodScent.
- **KEEN** — guarantees crit on the next physical hit. PersistUntilConsumed. Applied by Stalk.

**UseHitCount pattern:** Stackable buffs like MOMENTUM use a `UseHitCount` flag on the buff effect. When set, token count equals the number of targets actually hit by that skill cast — not a fixed authored number. CrimsonRhythm hitting 3 enemies grants 3 MOMENTUM stacks. Missing all enemies grants 0. This is the standard pattern for skills that reward hitting multiple targets.

**HoTs** (tick on recipient's TurnStart):

| HoT | Formula |
|-----|---------|
| Regen | MaxHP × 10% per tick |
| Vivify | MaxMP × 10% per tick |
| Rejuvenate | MaxHP × 10% + MaxMP × 10% per tick |

---

## PROGRESSION — XP, LEVELS, STAT GROWTH

### XP & Leveling

- XP is earned from combat, per enemy defeated.
- Level up = **automatic base stat growth** + **player choice allocation** (currently implemented as a 3-choice pick from generated stat options).
- Max level: 99 (final). Current MVP cap: 5.
- **RESONANCE is separate** — shared party resource for mnemonic acquisition, not tied to XP.

### Dual-Layer Stat Growth

| Layer | Description | Agency |
|-------|-------------|--------|
| **Base Growth** | Automatic per level. Varies by character — reinforces identity. | None |
| **Choice Allocation** | Player picks from generated stat options at each level-up. | Full control |

Base growth ensures characters remain viable regardless of allocation. Choice allocation enables specialization.

### Enemy AI

Enemies use the same skill resolution pipeline as the player. The AI layer only decides which skill and which target.

**Two decision strategies:**
- **Scripted (Gambit-style):** ordered priority list of condition → action rules. Evaluated top-to-bottom; first match wins. Used for standard encounters.
- **Utility Scoring:** every (skill, target) pair scored against current board state. Highest score wins with a small random band. Reserved for bosses and elites.

**Behavior Profiles** (for utility scoring):

| Profile | Bias |
|---------|------|
| Feral | Near-random, chaotic |
| Predator | Target the weakest / finish low HP |
| Bully | Pile on already-afflicted targets |
| Tactician | Spread control/ailments |
| Guardian | Protect allies, sustain |
| Berserker | Maximum raw damage, ignores ailments |

### Enemy Information Reveal

Enemy data is not fully visible on first encounter. Information persists permanently in save data per enemy type.

- **Always visible:** name, race/type.
- **Discovered by hitting:** damage type weaknesses and resistances — revealed automatically when triggered during combat.
- **Discovered post-combat:** XP reward, loot table, enemy skills witnessed in combat.

---

## GEAR SYSTEM

### Slots

Each character has:
- **1 Weapon slot** — always equipped; weapon type varies per character (e.g., Skugge uses daggers/swords, not bows).
- **1 Armor slot** — armor weight class varies per character (Light/Medium/Heavy).
- **4 Open slots** — accept any mix of accessories (Shield, Boots, Cloak, Ring, etc.) or consumable items (Potion, Antidote, Bomb, etc.) freely. No pouch/bag abstraction. Consumables sit directly in slots like gear.

In combat, the ITEM card lists whatever consumables are currently in a character's open slots. Every consumable slot is a slot not filled by combat gear — that tradeoff is the design.

### Rule: One of each type per character

No duplicate gear types in the same loadout (e.g., no two shields). Exception: rings, if implemented.

### Stat Modifiers

Gear provides flat stat modifiers (ATK, DEF, etc.) and elemental resistance values. Gear identity comes from what stats and resistances it provides, not from unlocking skill access.

### Swapping

Loadout is locked at dungeon/rest-point entry. No mid-dungeon swapping. Preparation matters.

### Item Effects

Consumable items use the same effect base as mnemonics — the pipeline handles both. The distinction is in the subclass: `Item_Effect_*` subclasses use flat fixed values (no stat scaling, no crit, always resolve). `Skill_Effect_*` subclasses use the full formula. A Potion doesn't care about your Phys.Atk.

---

## RESONANCE ECONOMY

RESONANCE is a **shared party resource** — not per-character. Dropped by enemies, found in chests. Spent to scribe new mnemonic instances from the Compendium, or to invest in mnemonic upgrades (rank progression).

Scarcity is the design lever. Rare enough that every spend is a real decision: new mnemonic vs. ranking up an existing one vs. scribing a copy for a second character. Drop tables control tuning.

No performance scoring, no opaque calculation. RESONANCE is loot.

---

## ENCOUNTER DESIGN

Encounters are **random within authored zones** — no visible overworld enemies. Every zone has a hand-configured enemy pool and encounter rate. Individual encounters within a zone are drawn from that pool; the mix of enemies per fight can be randomized within authored groups (e.g., "2–3 Draugr" or "1 Draugr + 1 Hexer").

Special encounters — scripted fights tied to story beats — bypass the random system entirely and trigger on specific overworld events or zone transitions.

Rest points restore HP and MP and are the only location where loadout can be swapped. The dungeon remains a two-axis attrition puzzle: HP and MP both drain across encounters; both restore at rest. Arrive at the boss in the right shape.

Encounter difficulty is tuned assuming players may arrive depleted.

### Encounter Rate Modifiers

The step counter reads a **party-wide encounter rate multiplier** before each check. Default value: `1.0`. Consumables can write to this value for a fixed duration (in steps).

| Item | Effect | Duration |
|------|--------|----------|
| Smokescreen | Rate × 0.0 (encounters disabled) | 30 steps |
| Incense | Rate × 0.5 (encounters halved) | 60 steps |

Effects don't stack — the most recently applied modifier wins. Duration is consumed by movement, not time.

These are consumable items occupying an open gear slot. The slot trade-off is the cost.

### Encounter-Free Zones

Areas without an `EncounterComponent` never trigger random encounters. Puzzle rooms are always encounter-free. No special logic required — the absence of the component is the design.

Scripted fights in encounter-free areas trigger through explicit story events, bypassing the random system entirely.