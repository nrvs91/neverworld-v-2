# NEVERWORLD — Game Design Document V2 (Rewritten)

> This document is the design source of truth for NEVERWORLD V2.
> This is a living document. Stubs and TODOs are intentional — fill them as design crystallizes.
> **Last updated:** 2026-06-05 — Skill system overhaul: vertical-only progression, gear-based slots, per-mnemonic character ownership, float Power values.

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

Skills are Mnemonics — physical objects that encode technique, combat knowledge, and concentrated belief. You don't learn a skill, you run a mnemonic. You don't train an ability, you carry one.

In NEVERWORLD's post-singularity setting, the boundary between information and matter has eroded. The unconscious layer — where emotion, belief, and hyperstition accumulate — seeps into physical reality wherever the signal is strong enough. Mnemonics are nodes where that layer punched through and crystallized. Some predate living memory. Nobody knows who encoded the first ones. They exist, they work, and that's enough.

This is hyperstition made literal: a technique that became real because enough people believed it, used it, and passed it on. The mnemonic works because it has always worked. Belief and matter are the same thing here.

**Mechanically:** Mnemonics are discrete, ownable items — not entries in a character-locked tree, not stat unlocks, not class features. Each instance is its own object. Skugge's copy and Vargi's copy are two separate things. They grow and get lost. Think equipment, not abilities.

Each mnemonic is usable by one or more specific characters. Some mnemonics are unique to a single character — Uskrav belongs to Skugge alone. Others are shared across characters who can sensibly use them — Blodspor might belong to both Skugge and Vargi, since any sharp weapon can cause bleed.

The `character_owner` field lists eligible characters. There is no "equip anything on anyone" — the lock is real, but it's authored per-mnemonic, not per-character.

---

### Skill Construction

A mnemonic is a **data resource** — a `.tres` file, not a script. It holds cost metadata, ownership data, a power multiplier, and an ordered list of **effect steps.** There is no skill logic in the mnemonic itself. Logic lives in the effect components.

```
Mnemonic (SkillClass_Base)
├── character_owner (String or Array — "skugge" for single, ["skugge", "vargi"] for shared)
├── ap_generates (int — positive generates AP, zero is neutral)
├── ap_generation_bonuses (Dictionary — token→bonus pairs, e.g. {"shield": 1})
├── ap_cost (int — positive consumes AP, zero means no AP cost)
├── ap_reduction_conditions (Dictionary — token→discount pairs, e.g. {"poison": 3})
├── HPCostPercent, MPCost
├── IsMelee, TrueStrike
├── Power (float — multiplier on AtkStat, see Damage Formula)
└── EffectSteps[]
      ├── Skill_Effect_Damage   (step 1 — hit the target)
      └── Skill_Effect_DoT      (step 2 — apply poison if step 1 hit)
```

A mnemonic that both generates AND costs AP (hybrid) uses both fields. A generator-only mnemonic sets `ap_cost = 0`. A consumer-only mnemonic sets `ap_generates = 0`. A neutral mnemonic sets both to zero.

`ap_reduction_conditions` maps token type strings to per-token AP discounts. If a mnemonic has `{"poison": 2}` and the target has 3 POISON tokens, the effective AP cost is reduced by 6 (3 tokens × 2 discount each). Discounts are calculated at validation time and never reduce cost below 0.

`ap_generation_bonuses` works identically in the opposite direction — maps token type strings to per-token AP generation bonuses. If a mnemonic has `{"shield": 1}` and destroys 2 SHIELD tokens on the target, it generates +2 bonus AP on top of its base `ap_generates` value. Bonuses are calculated at validation time, capped by AP cap (10).

Token-level AP modifiers (ALACRITY granting +1 AP per turn, gear passives adding +1 to all AP generation) are separate — they are universal board-state modifiers that stack with the mnemonic's authored values.

Each effect step is its own resource — a self-contained component that knows what it does, what stats it reads, and what token it creates. The execution pipeline iterates the list and resolves each step in order. The mnemonic is passive data. The effects are the behavior.

#### Effect Vocabulary

Effect classes are **dispatch mechanisms only** — they carry no behaviour. All logic lives in the RuntimeToken subclass that each effect references. There are three effect types:

| Effect | What it does |
|--------|-------------|
| `Skill_Effect_Instant` | Duplicate the referenced token blueprint, set source/owner, call `fire(context)` immediately. Used for damage, finishers, and instant heals. Token is discarded after firing — never stored. |
| `Skill_Effect_Grant` | Duplicate the referenced token blueprint `amount` times, add each instance to `target.tokens`. Used for DoTs, buffs, debuffs, ailments, reactions, marks — anything persistent. |
| `Skill_Effect_Remove` | Remove active tokens of a given type from the target. Used for cleanse effects. |

The behaviour of any given effect is entirely determined by the `RuntimeToken` subclass attached to it. A `Skill_Effect_Grant` that references `RuntimeToken_Poison` applies a DoT. The same `Skill_Effect_Grant` referencing `RuntimeToken_Empower` applies a damage buff. The effect class doesn't care — it only knows how to dispatch.

Items and mnemonics share the same execution pipeline and effect classes. The distinction: item effects use flat fixed values (no stat scaling, no crit); mnemonic token classes use the full formula.

#### Damage Formula

Each `Skill_Effect_Damage` step has a hand-authored float **Power** value. Damage resolves as:

```
damage = (AtkStat × Power) / (DefStat + 10) × Random(0.85, 1.0)
```

- **Power** — authored per effect as a float. 1.0 = 100% of AtkStat (basic attack baseline). 2.5 = 250% of AtkStat. 0.5 = 50% of AtkStat. The number directly communicates "× basic attack damage."
- **AtkStat** — attacker's relevant stat: Phys.Atk for physical, Magic.Atk for magical.
- **DefStat** — defender's relevant stat: Phys.Def or Magic.Def.
- **+10 offset** — softens defense scaling at low values, prevents division by near-zero.
- **Random(0.85–1.0)** — variance roll. Same spread as Pokémon.
- Result rounded to int; minimum 1.

No level multiplier — AtkStat already reflects level progression through dual-axis stat growth. A separate level term would double-amplify it.

**Power ceiling:** TBD. The range is expected to land somewhere between 0.5 (light setup skills) and 4.0+ (heavy AP spenders), with the true ceiling determined through playtesting against the AP economy.

**Multi-stat scaling:** The current formula uses a single AtkStat. Some mnemonics may need to scale off multiple stats — e.g., a skill that uses both Phys.Atk and PULSE. The formula will be extended to support this when such skills are authored. The extension is expected to be a weighted sum or multiplicative blend of the relevant stats, replacing the single AtkStat term.

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

### Skill Categories

Mnemonics are standalone tools. They do not modify other mnemonics. No "support gem" logic — no linking a damage skill to a support skill for amplified effects. Each mnemonic is self-contained.

Mnemonics can serve any combat role:

| Category | Examples |
|----------|----------|
| Damage | Uskrav (slash), Mørkeblad (shadow strike) |
| DoT | Blodspor (bleed), Ember Brand (burn) |
| Heal | Vivify (restore HP), Rejuvenate (HP + MP) |
| Buff | Iron Will (raise Phys.Def), Alacrity (+PULSE) |
| Debuff | Weaken (lower enemy attack), Fracture (lower defense) |
| Cleanse | Purge (remove ailments), Dispel (remove debuffs) |
| Stance | Stoneguard (defensive), Frenzy (offensive tradeoff) |
| Reaction | Counter (retaliate on hit), Vigil (heal damaged ally) |

Each character's mnemonic pool is authored to give them a coherent toolkit. Skugge gets daggers, shadows, and speed. Vargi gets heavy strikes, tanking, and raw power. Milis gets fire, ice, and signal-weaving. Some overlap is fine — Blodspor might belong to both Skugge and Vargi — but each character's core identity lives in their unique skills.

---

### Skill Ranks

Skills have ranks. Higher rank means higher Power, better AP economy (more generation or lower cost), occasionally a small mechanical refinement — not arbitrary resistance flags. A low-rank skill against a high-defense enemy does pathetic damage. The numbers tell the story. No "RESIST" labels needed.

This is the core pressure to engage with the RESONANCE system. Ignoring skill investment doesn't lock you out — it just makes you ineffective in a way that's immediately legible. Low Power can't compensate for a widening stat gap as the game progresses.

Progression is vertical, not branching. Rank II is the same skill as Rank I — same identity, same role, better numbers. No permanent reforge decisions, no locked-off paths. What you see in the rank chain is what you get.

---

### Mnemonic Progression

All mnemonic progression is driven by RESONANCE — the party's shared resource. Spending RESONANCE advances a mnemonic vertically along its rank chain: Rank I → Rank II → Rank III. No detours, no mutations, no take-backsies needed.

The upgrade path is linear by design. RESONANCE investment upgrades a skill vertically, and that's it. Rank II is Rank I with better numbers. Rank III is Rank II with mastery numbers and maybe a small refinement that reinforces what the skill already does. The skill's identity never changes — Uskrav at Rank III is still a fast dagger generator, just a scarier one.

There is no respec because there is nothing to respec. The only decision is whether to invest RESONANCE in a given mnemonic or not.

#### Mnemonic Graph

Every mnemonic displays its full rank chain from the moment it enters your possession. **No obfuscation.** The player can inspect any mnemonic in the party's collection — equipped or sitting in inventory — and see every rank, every Power value, every cost, every special. Locked nodes display their upgrade cost. Unlocked nodes display what you've already committed. The entire chain is visible upfront.

The graph is a planning tool as much as a status screen. You invest RESONANCE with full knowledge of what you're buying. No surprises, no hidden branches, no gotchas.

#### Chain Design Principles

**Three ranks is the default.** Base → II → III. Some mnemonics may have fewer (complete at base — the skill is finished the moment you acquire it). Some may have more (rare, only when the skill's role genuinely justifies deeper investment). Depth reflects the skill's importance in the game's toolkit, not its quality.

**Vertical ranks: same identity, better numbers.** The primary lever is Power. Rank II might add a small mechanical refinement — a nudge that rewards familiarity without changing the skill's role. Rank III is mastery: a slight twist that says "you committed to this." But the skill is still the skill. A generator stays a generator. A consumer stays a consumer.

**Costs are tools, not progression rules.** AP generation/cost and HP% costs don't automatically change as a skill ranks up. They change only when that change means something. If the cost stays flat across all three ranks, that is a design decision, not a missed opportunity.

#### Worked Example: Uskrav Chain

Skugge's starting dagger skill. A straightforward three-rank chain — most mnemonics will look like this.

| Node | Power | AP | HP% | Special |
|------|-------|----|-----|---------|
| Uskrav | 1.5 | +1 | 15% | — |
| Uskrav II | 2.0 | +1 | 15% | — |
| Uskrav III | 2.5 | +1 | 15% | +1 bonus AP on crit |

**Trunk (I→II→III):** AP generator. Same HP cost (15%), same +1 AP generation, increasing Power (1.5 → 2.0 → 2.5). Rank III adds the refinement: +1 bonus AP on critical hit. This rewards mastery — the player who builds around Uskrav's crit profile gets more fuel — without changing the skill's identity. It's still a fast, cheap generator. It just gets greedier if you're good with it.

The progression is legible at a glance. Every rank is a better version of the same tool. The RESONANCE investment is paying for Power growth and, at the capstone, a mechanical edge that makes the skill feel complete. No branch anxiety, no permanent lockouts, no "what if I'd gone the other way." Just a dagger skill that gets sharper the more you commit to it.

---

### Acquisition

Mnemonics are physical objects and enter the party's possession as such.

- **Loot** — dropped by enemies or found in chests. Pick it up, it's yours, equip it immediately if you want.
- **Purchase** — some mnemonics are sold by merchants. Standard item transaction, no additional friction.
- **Unique** — certain mnemonics are one-of-a-kind. They exist once in the world. Uniqueness is about scarcity, not complexity.

There is no catalogue, no scribing, no discovery layer. A mnemonic you don't have is one you haven't found yet.

---

## RESOURCE SYSTEM

### AP — Player-Exclusive Action Engine (combat only)

**AP is player-exclusive.** Only player characters have AP bars. Enemies do not use AP — their behavior is driven by patterns and cooldowns (see Enemy AI).

**AP is action-generated, not time-generated.** Characters do not gain AP passively at turn start. AP is earned by using mnemonics that generate it.

- **Generator mnemonics** — produce AP when used. Your bread-and-butter skills: deal damage, apply tokens, AND feed your engine.
- **Consumer mnemonics** — cost AP to use. Finishers, powerful buffs, detonators, nukes. Bigger effect, higher cost.
- **Neutral mnemonics** — neither generate nor cost AP. Standalone utility: buffs, debuffs, stances.
- **Hybrid mnemonics** — have both an AP cost AND a conditional refund. "Costs 9 AP, but 3 cheaper per POISON on target."

**AP cap: 10.** Universal, no exceptions. Generation past cap is lost — spend it or waste it.

**AP resets every encounter.** Clean slate each fight. No carry-over, no pre-boss farming.

**Starting AP:** characters begin each encounter at 0 AP. Some gear may grant starting AP (e.g., "Amulet of Readiness: +2 starting AP").

**Basic attack (inherent action):** every character always has access to a basic attack. It costs no AP, generates +1 AP, and deals baseline physical damage (Power 1.0, weapon damage type, no token interaction). It is intentionally plain — an AP floor, not a combat tool. Mnemonics and gear modify it: passives that add AP on crit, multi-hit properties, token application on hit. The basic attack is a modifiable platform, not a wasted turn.

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

Identity is **enforced at the mnemonic level.** Each mnemonic has a `character_owner` tag. Skugge owns Uskrav — Vargi can't equip it. Blodspor might be shared between Skugge and Vargi, authored that way. The stat growth and gear access still telegraph who a character *should* be, but the hard gate is the mnemonic ownership system. No one is equipping Milis's fire spells by accident.

**Stats** — the primary soft signal. Each character has different stat growth, making them naturally better at their own mnemonics. Vargi healing with a magic mnemonic works in theory; his Magic stat makes it weak. The numbers communicate the misfit even where ownership doesn't block it.

Stat growth has two components:
- **Natural growth** — hand-authored per-level increases, different per character.
- **Choice growth** — on level-up, pick one stat from three randomly generated options. Small nudges over time. Cumulative choices can bend a character slightly off their default lane.

**Gear** — weapon type and armor class vary per character, reinforcing their stat identity structurally. A Skugge in heavy plate is possible (if you find it), but it won't feel good.

**Mnemonic slots** — not a flat per-character pool anymore. Slot count comes from your equipped gear: weapons carry 1–2 slots, armor 0–1, accessories 0–1. A typical Skugge with a 2-slot dagger, 1-slot leather armor, and 1-slot ring has 4 active mnemonics. A Vargi in 0-slot heavy plate with a 1-slot axe has 1. The spread across your roster and gear collection creates natural variety in how many tools a character brings to combat.

The slot system is intentionally flat — any mnemonic goes into any slot. Future categorization (Action vs. Stance slots, linked pairs, etc.) is reserved for post-demo evaluation. Only if the system calls for it.

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
| `TurnStart` | Tick CT for all non-downed actors, find highest-priority ready actor. Active actor's `OnTurnStart` tokens tick: DoT damage, HoT healing, duration countdown, expired tokens removed. Token-based AP modifiers (e.g., ALACRITY) resolve here. Emit `TurnStarted`. |
| `ActionSelect` | Emit `please_select_action`. Await `action_selected(skill, target)` signal. The FSM is actor-agnostic — `PlayerInputComponent` fires the signal for player actors, `AIBehaviorComponent` fires it for enemies. The FSM does not branch on actor type. |
| `ActionExecution` | Delegate to `ActionPipeline` — calls `pipeline.run()` and awaits `pipeline_complete`. The FSM does nothing else in this state. ActionPipeline owns the full execution cycle: announce, PRE-pass, primary skill execution, POST-pass, downed detection. |
| `TurnEnd` | Consume CT, emit `TurnEnded`, check win/loss condition |
| `CombatEnd` | Emit `CombatEnded`, hand off to post-combat flow (XP, loot, exit) |

### UI FSM States

| State | Responsibility |
|---|---|
| `CombatStart` | Fade in, present opening, spawn actor visuals |
| `TurnStart` | Highlight active actor (namecard offset bump). Branch on actor type: player-controlled → transition to `ActionSelect`. Enemy → transition to `EnemyActing`. |
| `EnemyActing` | Enemy turns only. Show active enemy namecard highlight, dim player UI. Wait for execution to complete, emit `PresentationReady`. |
| `ActionSelect` | Show command menu, skill list, tooltips |
| `Targeting` | Cursors on valid targets, input cycling — covers skills and items |
| `TacticsInspect` | Cursors on all actors, inspect panel on confirm |
| `ActionExecution` | Skill banner, animations, floating numbers, bar updates |
| `ReactionScan` | Present reaction firing |
| `TurnEnd` | Bar updates, downed presentation |
| `CombatEnd` | Victory/defeat screen, XP flow |

### Design Notes

**Why the FSM doesn't branch on actor type**

During `ActionSelect`, the FSM emits `please_select_action` and waits for `action_selected(skill, target)`. It never asks whether the active actor is a player or an enemy. The actor's own component handles that: `PlayerInputComponent` surfaces the menu and waits for input, `AIBehaviorComponent` runs its decision and fires immediately. The FSM only knows that a decision has been made.

Any FSM that branches on actor type effectively has two versions of every state. Adding a new actor type — a summoned ally, a charmed enemy, a guest NPC — means touching the FSM. The component model absorbs that variation without the FSM noticing.

**Why ActionExecution delegates to ActionPipeline**

`ActionExecution` calls `pipeline.run()` and awaits `pipeline_complete`. That's the entire state. `ActionPipeline` is a dedicated Node — a sibling of `CombatFSM` under `CombatScene` — that owns the full execution cycle. The FSM's only job here is to delegate and wait.

ActionPipeline runs in three phases: a **PRE-pass** (reaction tokens that fire *before* the primary, and may cancel it), the **primary skill execution**, and a **POST-pass** (reaction tokens that fire after and need the primary's result). Each pass iterates directly over all actors' token lists and calls `check_trigger(context)` on each reaction token. No signal connections, no connect/disconnect lifecycle. Tokens self-select into the queue; the pipeline never needs to know they exist in advance.

**Why PRE and POST are the right two windows**

Some reactions must fire *before* the primary resolves — HAMEDO (hit the attacker before they act), PREMONITION (nullify the spell before it lands). A post-only scan can't express that. Some reactions genuinely need the primary's result — COUNTER needs to know the hit landed; VIGIL needs to know who took damage and for how much. Collapsing both into one scan forces artificial ordering workarounds.

PRE and POST are the natural split. PRE is "before the primary resolves." POST is "after." Within each pass, order is deterministic — direct array iteration over the actors list, not signal connection order. The window closes after POST. No chains between windows; Tier 2 output reopens nothing.

**Why not every token that responds to combat is a reaction**

PRE/POST pass tokens are for effects that need a temporal window around the primary action. Not everything qualifies. Passive tokens are checked inline during damage resolution — they modify *how* something resolves, not *when* relative to the primary. The distinction:

| Token | Type | Resolution point |
|---|---|---|
| COVER / INTERCEPT | Passive | `RuntimeToken_Damage.fire()` — target redirect before damage calc. Protectee is always targetable; effects aimed at them resolve on the protector instead. AoE dedup: protector takes 1 hit max per action regardless of how many targets redirect to them. |
| BRACE / Shield | Passive | `RuntimeToken_Damage.fire()` — damage modifier during calc |
| HAMEDO | PRE reaction | ActionPipeline pre-pass — fires before primary, may down the attacker and cancel the action |
| PREMONITION | PRE reaction | ActionPipeline pre-pass — sets `context.negated = true`, primary skipped |
| COUNTER | POST reaction | ActionPipeline post-pass — fires after primary lands |
| VIGIL | POST reaction | ActionPipeline post-pass — heals the damaged ally after primary resolves |
| FOLLOW UP | POST reaction | ActionPipeline post-pass — fires after an ally hits |

The rule: if the effect modifies *how Z works* or *redirects A to B*, it is passive state checked inline. If it is *when X happens, do Y* with a genuine before/after window, it belongs in a pass.

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

### Hit / Miss Formula

Physical skills only:
```
hitChance = clamp( (attacker.HIT × ChanceTier%) / defender.DODGE, 5%, 95% )
```

5% floor means nothing is impossible; 95% ceiling means nothing is guaranteed.

**Magical skills always hit.** No accuracy check. The trade-off: magic is reliable but cannot crit (see Crit System below).

### Crit System

- Crits are **physical only.** Magical skills auto-hit but can never crit.
- Baseline 5% crit chance on physical skills (authored per skill, not global).
- Crit = 2× damage.
- KEEN buff (stackable=false, persists until consumed) guarantees crit on the next physical hit.

### Resistance & Damage Types

**Physical damage types:** Slash, Pierce, Blunt.
**Elemental damage types:** Fire, Water, Air, Nature, Stone, Feral.

Every damage type has a resistance state per actor. Three states:

| State | Damage | Ailment / DoT application |
|-------|--------|--------------------------|
| WEAK | 2× | 2× chance |
| — (none) | 1× | 1× chance |
| RESISTANT | 0.5× | 0.5× chance |
| IMMUNE | 0× | 0% — cannot land |

**IMMUNE** is a hard wall. Tokens and debuffs cannot overwrite it. Only skills with the BYPASS flag ignore it.

Resistance states are **authored directly on enemies** via `ResistanceProfile`. For players, the profile is **compiled from equipped gear** at combat start and remains static for the duration of combat.

**Token interactions** — tokens can grant RESISTANT or WEAK to any non-IMMUNE type. Opposing states cancel to neutral (WEAK + RESISTANT token = none). IMMUNE cannot be touched by tokens.

**DoT behaviour** — DoTs (BURN, POISON, BLEED) always land if the skill hits, regardless of resistance state. IMMUNE is the exception.

**DoT reapplication** — Reapplying a DoT that is already active on a target extends the existing token by adding the new charges to the current remaining charges, capped at 9. No second stack is created. Charges represent duration only — tick damage is flat per the formula above regardless of how many charges remain. (9 is the cap: single digit, UI-friendly, and unreachable in normal play without deliberate setup.)

The distinction matters: fire-IMMUNE means zero fire damage, but FREEZE still lands and functions normally.

### AP Economy

AP is a **player-only, action-generated resource.** There is no passive AP income. The economy is entirely driven by what the player chooses to do each turn.

**AP generation rules:**
- Using some mnemonics produces AP, some are neutral, and some consume AP to either modify their effects or need AP to be used.
- The basic attack (inherent action) always generates +1 AP.
- Tokens (ALACRITY, etc.) can grant additional AP per turn or per action.
- Gear can grant flat starting AP at combat start or +1 to all generation.

**AP consumption rules:**
- Using a consumer mnemonic costs AP equal to its `ap_cost` value, minus any active `ap_reduction_conditions`.
- AP cannot go negative. A skill the player can't afford is greyed out.
- There is no refund on miss or cancel — the cost is paid on execution.

**Economy rhythm:**
Every fight begins at 0 AP and the player builds their engine through action. Generators feed the engine while dealing damage or setting up tokens. Consumers cash out the built AP for high-impact effects — finishers, burst damage, party heals, conditional detonators. Neutral skills provide utility without affecting the economy. Hybrid skills reward setup by reducing their own cost based on board state.

The decision each turn is: **am I building, spending, or neutral?** The answer changes as the fight progresses. Early turns are engine-building. Mid-fight is deciding when to cash out. Late fight is cashing out under pressure with depleted HP/MP.
The "Roles" below are just to illustrate a trend, there is no such destinction in game. Purely illustratory:

| Role | AP Effect | Skill Class |
|------|-----------|-------------|
| Generator | +1 to +2 AP | Bread-and-butter attacks, setup skills, token applicators |
| Neutral | 0 AP | Stances, buffs, debuffs, utility |
| Consumer | -2 to -4 AP | Strong attacks, detonators, burst skills |
| Finisher | -5 to -9 AP | Fight-changing nukes, party-wide effects |
| Hybrid | costs AP, refunds on condition | Conditional payoff skills |

### Skill Costs

Physical skills (weapon/physical mnemonics) cost **HP%** + AP (if consumer) or generate AP (if generator).
Magical skills (elemental mnemonics) cost **flat MP** + AP (if consumer) or generate AP (if generator).
AP generation and consumption are independent of the HP%/MP tier — a heavy physical skill can be a generator, and a minor skill can be a consumer. The AP role reflects the skill's function in the economy, not its raw power level.

### Basic Attack (Inherent Action)

Every character has access to a basic attack at all times. It does not consume a mnemonic slot and is always available.

| Property | Value |
|----------|-------|
| AP | Generates +1 AP |
| Power | 1.0 (100% of AtkStat — the baseline) |
| Damage type | Character's weapon type |
| Crit | Yes |
| Token interaction | None by default |

The basic attack is intentionally plain — it is an AP floor, not a combat tool. It exists so the player is never fully locked out: if all equipped mnemonics are currently unaffordable, the basic attack can always be used to build AP.

**Mnemonic and gear passives can modify the basic attack.** A passive mnemonic might add "+1 AP when basic attack crits." A weapon might change the damage type or add multi-hit. A gear item might add poison-on-hit. Building around a modified basic attack is a valid loadout strategy.

### Death

- 0 HP = **Downed.** Cannot act. Revivable mid-combat.
- All party members downed = **Game Over.** Return to last save.
- No permadeath.

---

## COMBAT — RIPPLE FRAMEWORK

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

Every combat effect — from a basic sword slash to a three-turn BURN to a reactive counter stance — is a **token.** Tokens are self-resolving objects. They are created from a blueprint (the skill's authored data), attached to a target, and handle their own lifecycle from there. The combat system doesn't need to know what kind of token it's dealing with — it creates them and lets them run.

A token has four properties:

- **Owner** — the character carrying this token (who it's attached to)
- **Source** — the character who created it (matters for damage scaling)
- **Trigger** — when this token fires (Instant, OnTurnStart, OnTurnEnd, OnDamageTaken, etc.)
- **token_type** — string key used for deduplication, display, and mutual cancellation

**Quantity = duration.** There is no charges counter. "3 POISON" means three separate POISON token instances on the target. Each tick or use consumes one instance. 3 POISON → 3 ticks → 3 turns. 3 EMPOWER → 3 turns of damage buff. The count visible in the UI is always a live instance count.

**The trigger determines the token's lifetime:**

| Effect | Trigger | Quantity | What Happens |
|--------|---------|----------|-------------|
| Sword slash | INSTANT | 1 | Created, fires immediately, discarded |
| BURN (3 turns) | ON_TURN_START | 3 | One instance ticked and consumed at start of owner's turn |
| EMPOWER (3 turns) | ON_TURN_END | 3 | Passive multiplier (×1.5) read during damage calc; one instance expires at end of owner's TurnEnd. Cast turn is free — 3 tokens = 3 boosted attacks |
| WEAKEN (3 turns) | ON_TURN_END | 3 | Passive multiplier (×0.75); ticks at end of *target's* turn |
| STUN | — | 1 | Consumed by CombatFSM at TurnStart; action is skipped |
| COUNTER | ON_DAMAGE_TAKEN | N | POST-pass reaction — retaliates against attacker after taking damage |
| VIGIL | ON_ALLY_HIT | N | POST-pass reaction — heals a damaged ally after primary resolves |
| ENVENOM | INSTANT | 1 | Consumes all POISON on target; damage = count × power_per_token |
| Brace | Passive (future) | 1 | Checked inline during damage calc — reduces incoming damage, then expires |
| KEEN | Passive (future) | 1 | Guarantees crit on next physical hit, consumed on use |

**Tokens are objects, not counters.** A BURN token is a discrete thing attached to a character. It can be transferred, cleansed, or detonated.

**Passive vs Reaction:** Not every token that responds to combat needs a trigger window. Passive tokens (EMPOWER, WEAKEN, BRACE) are polled inline during damage resolution. Reaction tokens (COUNTER, VIGIL) need the primary action to fully resolve first — they belong in the PRE or POST pass. The rule: if it modifies *how* something works, it's passive. If it fires *because* something happened, it's a reaction.

**Mutual cancellation:** tokens can declare an `opposes` type. Applying EMPOWER to a character who has WEAKEN cancels one WEAKEN instance instead of stacking — the two can never coexist.

**ActionPipeline is the orchestrator, not a resolver.** It announces the action, runs the PRE-pass, validates execution, calls `SkillExecutor.execute(context)`, runs the POST-pass, and emits `action_resolved(context)`. It never calculates damage or resolves effects itself. The tokens resolve themselves. `CombatCalculator` is a pure utility that token classes call when they need math — it doesn't drive the flow.

**Multi-step skills and conditional chaining:** A mnemonic's effect list is an ordered sequence of steps. Each step can read what the previous step did via a shared scratch pad (resolution context). This enables conditional effects — Viper Strike is two steps: (1) deal Pierce damage, (2) apply 3 POISON tokens *if step 1 hit*. The Grant step has `needs_previous_hit = true` — if the damage missed, no poison. The scratch pad is internal to a single skill use and discarded afterward — it is not token state.

**Generator / Detonator pattern:** Skills are designed as combo pieces. Every skill must have standalone value — combo payoff is the ceiling, not the floor. Viper Strike generates POISON; Envenom detonates it for burst damage scaling with stack count. Full combo lines unlock gradually across progression.

### Status Effects Reference

**Ailment HitChance** — authored per skill as a discrete tier. Applied after the skill lands, before resistance is checked.

| Tier | Base Chance |
|------|-------------|
| CERTAIN | 100% |
| HIGH | 75% |
| MEDIUM | 50% |
| LOW | 25% |

`landChance = min(HitChance × resistMult, 100%)` — IMMUNE skips the formula entirely and returns 0%.

This is separate from Hit/Dodge, which governs whether a physical skill connects at all.

**Elemental CC Ailments** (apply-chance gated, resistance blocks landing):

| Ailment | Effect |
|---------|--------|
| FREEZE (Water) | Action loss / speed debuff |
| PETRIFY (Stone) | pretty much the same as a KO status, indifinite stun, petrify = basically dead, just brought back online via different means |


**Elemental DoTs** (always land if skill hits; resistance state scales tick damage):

| DoT | Tag | Tick Formula | Passive Effect |
|-----|-----|-------------|----------------|
| BURN | Fire | MaxHP × 10% × resistMult | +fire damage taken while active |
| POISON | Nature | MaxHP × 10% + MaxMP × 10% × resistMult | — |
| BLEED | Feral | MaxHP × 10% × resistMult | Healing reduction while active |

`resistMult: WEAK = 2.0 / none = 1.0 / RESISTANT = 0.5 / IMMUNE = 0.0`

**Buff / Debuff tick timing:**

Buffs and debuffs expire at **TurnEnd** of the actor carrying them. DoTs and CC ailments expire at **TurnStart**. This split means:
- A debuff applied to an enemy lands immediately on their next attack, then ticks down at the end of *their* turn — all authored duration is usable.
- A self-buff cast on your own turn gets a **free cast turn**: the first TurnEnd tick is skipped. 3 EMPOWER tokens = 3 boosted attacks, not 2.

**Special buffs (future):**
- **MOMENTUM** — +25% Phys.Atk per stack (physical only). Stacks consumed on next physical hit. Granted per enemy hit.
- **KEEN** — guarantees crit on the next physical hit. Consumed on use.
- **ALACRITY** — grants +1 AP at start of bearer's turn. Duration-based (e.g., 3 ALACRITY = 3 turns of bonus AP income).

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

Enemies do **not** use AP. Their behavior is driven by patterns and cooldowns — they select skills based on turn count, HP thresholds, or weighted random tables. The player's AP economy and the enemy's action economy are completely decoupled.

Enemies use the same skill resolution pipeline as the player. The AI layer only decides which skill and which target.

**Two decision strategies:**
- **Scripted (Gambit-style):** ordered priority list of condition → action rules. Evaluated top-to-bottom; first match wins. Used for standard encounters.
- **Utility Scoring:** every (skill, target) pair scored against current board state. Highest score wins with a small random band. Reserved for bosses and elites.

**Pattern types:**

| Pattern | Description |
|---------|-------------|
| Cooldown | Skill is available every N turns. "Fire Breath: use whenever available, 3-turn cooldown." |
| HP Threshold | Skill triggers when HP crosses a boundary. "Enrage: at 30% HP, use and refresh every 4 turns." |
| Sequence | Fixed rotation. "Turn 1: Howl, Turn 2: Bite, Turn 3: Bite, repeat." |
| Weighted Random | Skill has a weight; higher weight = more likely. Simple random without condition tracking. |

**Enemy readability:**
- Trash enemies: patterns are invisible. The player learns through observation — a VarnWolf that uses Howl every 3rd turn is a discovery, not a tutorial.
- Bosses and elites: may include a telegraph line before their big move ("The VarnWolf bares its fangs..."). Flavour text only — no mechanical indicator, no UI overlay. Oldschool feel.

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

Gear carries mnemonic slots. All gear — weapons, armor, and accessories — can hold mnemonics. Slot count varies per gear piece and is an authored property.

**Slot philosophy: flat, untyped.** Any mnemonic can go into any slot. The constraint is count, not category. A weapon with 2 slots means 2 active mnemonics for that character. An armor piece with 0 slots means no mnemonics from armor — just the stat padding.

**Demo targets:**

| Gear Piece | Slot Target | Notes |
|------------|-------------|-------|
| Weapon | 1–2 slots | Primary slot driver. More slots = more active skills. |
| Armor | 0–1 slots | Heavy armor may trade slots for defense. Light armor may grant a slot. |
| Accessory | 0–1 slots | Small bonus. Not every accessory needs a slot. |

A character with a 2-slot weapon, 1-slot armor, and 1-slot accessory has 4 active mnemonics. A character with a 1-slot weapon and 0-slot armor has 1. This is where the roster-building puzzle lives — you're not just picking your best gear, you're deciding how many tools each character gets to bring.

**Consumables** sit directly in gear slots. No pouch abstraction. In combat, the ITEM card lists whatever consumables are currently occupying slots on a character's equipped gear. Every consumable slot is a slot not filled by a mnemonic or passive gear piece — that tradeoff is the design.

#### Rule: One of each type per character

No duplicate gear types in the same loadout (e.g., no two shields). Exception: rings, if implemented.

#### Stat Modifiers

Gear provides flat stat modifiers (ATK, DEF, etc.) and elemental resistance values. Gear identity comes from what stats and resistances it provides, not from unlocking skill access.

#### Swapping

Loadout can be changed freely outside of combat. No dungeon lock. The preparation puzzle is "what do I bring?", not "can I change my mind?"

#### Item Effects

Consumable items use the same effect base as mnemonics — the pipeline handles both. The distinction is in the subclass: `Item_Effect_*` subclasses use flat fixed values (no stat scaling, no crit, always resolve). `Skill_Effect_*` subclasses use the full formula. A Potion doesn't care about your Phys.Atk.

---

## RESONANCE ECONOMY

RESONANCE is a **shared party resource** — not per-character. Dropped by enemies, found in chests. Spent to rank up mnemonics along their vertical chains.

Scarcity is the design lever. Rare enough that every spend is a real decision: rank up an existing mnemonic vs. saving for a new find. Drop tables control tuning.

No performance scoring, no opaque calculation. RESONANCE is loot.

---

## ENCOUNTER DESIGN

Encounters are **random within authored zones** — no visible overworld enemies. Every zone has a hand-configured enemy pool and encounter rate. Individual encounters within a zone are drawn from that pool; the mix of enemies per fight can be randomized within authored groups (e.g., "2–3 Draugr" or "1 Draugr + 1 Hexer").

Special encounters — scripted fights tied to story beats — bypass the random system entirely and trigger on specific overworld events or zone transitions.

Rest points restore HP and MP. Loadout can be changed freely outside of combat. The dungeon remains a two-axis attrition puzzle: HP and MP both drain across encounters; both restore at rest. Arrive at the boss in the right shape.

Encounter difficulty is tuned assuming players may arrive depleted.

### Encounter Rate Modifiers

The step counter reads a **party-wide encounter rate multiplier** before each check. Default value: `1.0`. Consumables can write to this value for a fixed duration (in steps).

| Item | Effect | Duration |
|------|--------|----------|
| Smokescreen | Rate × 0.0 (encounters disabled) | 30 steps |
| Incense | Rate × 0.5 (encounters halved) | 60 steps |

Effects don't stack — the most recently applied modifier wins. Duration is consumed by movement, not time.

These are consumable items occupying a gear slot. The slot trade-off is the cost.

### Encounter-Free Zones

Areas without an `EncounterComponent` never trigger random encounters. Puzzle rooms are always encounter-free. No special logic required — the absence of the component is the design.

Scripted fights in encounter-free areas trigger through explicit story events, bypassing the random system entirely.
