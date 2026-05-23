# NEVERWORLD — Reaction Architecture Design Log

> **Date:** 2026-05-21 (Part I) + 2026-05-22 (Part II — Epiphany)
> **Status:** Design crystallized, awaiting implementation plan
> **Scope:** The universal token-grant system. Reactions, buffs, debuffs, ailments, DoT, HoT — all persistent effects.

---

## Part I: The Problem and the Breakthrough

### The Problem We Started With

We built an `ActionPipeline` with PRE/POST passes for reactions. The pipeline collects tokens via `ActiveTokens.collect_triggers()`, checks conditions via `RuntimeToken.check_trigger()`, and fires them via `RuntimeToken.fire()`.

**Then we tried to implement COUNTER and hit a wall.**

Our damage formula is:
```
damage = Power × AtkStat / (DefStat + 10) × Random(0.85, 1.0)
```

**Power** is hand-authored per `Skill_Effect_Damage` step. Every damage source in the game — Uskrav, Viper Strike, enemy claws — has a Power value on its mnemonic.

**Reaction tokens have no Power.** A COUNTER token is just a `RuntimeToken` with `Trigger.ON_DAMAGE_TAKEN`. It doesn't carry a `Skill_Effect_Damage` step. It doesn't have a mnemonic. So when it fires, what Power does it use?

This isn't a coding problem. It's a **design contradiction**: our entire damage system is built around authored mnemonics, but reactions aren't mnemonics.

### The Failed Attempts

**Attempt 1: Universal COUNTER Token with Hardcoded Power**
```gdscript
class_name RuntimeToken_Counter
var power: int = 20
```
**Why it failed:** No progression. No tuning. UI shows "COUNTER ???". Every COUNTER in the game deals the same damage.

**Attempt 2: % Return Damage**
```gdscript
var counter_damage: int = int(incoming_damage * 0.5)
```
**Why it failed:** Degenerate case. Boss has COUNTER ×1. Player pokes with a weak hit (2 damage), eats 1 back, token gone for free.

**Attempt 3: Token Carries `payload_mnemonic` — The Breakthrough**
The user's insight: **COUNTER is a mnemonic. Just like Uskrav.**

```
COUNTER STANCE (mnemonic, AP=4, HP%=0)
└── Skill_Effect_Reaction
    trigger = ON_DAMAGE_TAKEN
    charges = 3
    payload_mnemonic = COUNTER STRIKE
```

The token is a **trigger wrapper**. The mnemonic is the **payload**.

### The Self-Reference Trap (And Escape)

If `COUNTER.tres` has two effect steps:
1. `Reaction` → grant 3× COUNTER tokens
2. `Damage` → Power=20

Then when the player **casts** COUNTER, `SkillExecutor.execute()` runs step 1 (grant tokens) **and then step 2** (deal immediate damage). Casting your stance also stabs the enemy. Wrong.

**The fix: Separate resources.**

```
COUNTER STANCE (mnemonic, AP=4)
└── Skill_Effect_Reaction
    trigger = ON_DAMAGE_TAKEN
    charges = 3
    payload_mnemonic = COUNTER STRIKE   ← DIFFERENT resource

COUNTER STRIKE (mnemonic, AP=0)
└── Skill_Effect_Damage
    power = 20
    damage_type = Pierce
```

- **COUNTER STANCE** is what the player casts. Costs AP. Grants tokens.
- **COUNTER STRIKE** is what the token executes. Never cast directly. Has the Power.
- RESONANCE upgrades bump both: more charges on stance, more Power on strike.

---

## Part II: The Epiphany — Container, Template, Instance

### The Realization

**All combat effects reduce to three layers:**

| Layer | What It Is | Godot Type | Example |
|-------|-----------|------------|---------|
| **Container** | Costs, description, targeting, bundle of effect references | `MnemonicResource` | "Viper Strike" — 2 AP, single target |
| **Template** | "Create a token with these settings" | `Skill_Effect_*` | "Create a DoT token, poison, 3 charges" |
| **Instance** | The thing attached to a character that actually executes | `RuntimeToken_*` | The POISON token ticking on the enemy |

**The mnemonic doesn't know what it does.** It just says: "I cost 2 AP, target one enemy, and here are my effect templates." The templates say: "Create this token with these settings." The token says: "When my trigger fires, I do this."

### The Unified Effect Family

**All persistent effects are the same architectural pattern: grant a token with N charges.**

| Effect Type | Token Trigger | Token Behavior | Data Lives |
|-------------|--------------|----------------|------------|
| `Skill_Effect_DoT` | `ON_TURN_START` | `tick()` reads `dot_tag`, looks up formula | **Inline** in token |
| `Skill_Effect_Buff` | `ON_TURN_START` | `tick()` applies modifier to stat | **Inline** in token |
| `Skill_Effect_Ailment` | `ON_TURN_START` | `tick()` applies status (stunned, silenced) | **Inline** in token |
| `Skill_Effect_Reaction` | `ON_DAMAGE_TAKEN` / `PRE_EXECUTION` | `fire()` executes `payload_mnemonic` via `SkillExecutor` | **External** — references another mnemonic |

**Reactions are not special.** They are just token grants whose payload is external rather than inline. The DoT token knows its own formula. The reaction token knows which mnemonic to execute.

### The Outliers: Instant Effects

| Effect Type | Token Trigger | Token Behavior | Persists? |
|-------------|--------------|----------------|-----------|
| `Skill_Effect_Damage` | `INSTANT` | `fire()` calculates damage, applies it, discards self | **No** |
| `Skill_Effect_Healing` | `INSTANT` | `fire()` restores HP, discards self | **No** |

Damage and healing are the **only** effects that don't create persistent tokens. They fire once and vanish. Every other effect in the game — DoT, buff, debuff, ailment, reaction, HoT — attaches a token that executes later.

### The Finite Template Library

The game needs **~10 effect templates**, total. Not hundreds. Not per-skill. Per **type**.

```
resources/effects/
  ├── damage_base.tres          ← power=0 (overridden per mnemonic)
  ├── heal_base.tres            ← heal_power=0
  ├── dot_poison.tres           ← dot_tag=POISON
  ├── dot_burn.tres             ← dot_tag=BURN
  ├── dot_bleed.tres            ← dot_tag=BLEED
  ├── buff_empower.tres         ← buff_type=EMPOWER, modifier=1.5
  ├── buff_keen.tres            ← buff_type=KEEN
  ├── debuff_slow.tres          ← debuff_type=SLOW, modifier=0.5
  ├── debuff_weaken.tres        ← debuff_type=WEAKEN, modifier=0.5
  ├── reaction_counter.tres     ← trigger=ON_DAMAGE_TAKEN
  ├── reaction_vigil.tres       ← trigger=ON_ALLY_HIT
  ├── reaction_hamedo.tres      ← trigger=PRE_EXECUTION
  └── reaction_follow_up.tres   ← trigger=ON_ALLY_HIT
```

**Finite. Predictable. Reusable.** A mnemonic references one or more templates and overrides fields:

```gdscript
# Viper Strike.tres
mnemonic_name = "Viper Strike"
ap_cost = 2
effect_steps = [damage_base, dot_poison]
  damage_base.power = 25
  damage_base.damage_type = Pierce
  dot_poison.charges = 3

# Counter Stance.tres
mnemonic_name = "COUNTER"
ap_cost = 4
effect_steps = [reaction_counter]
  reaction_counter.charges = 3
  reaction_counter.payload_mnemonic = counter_strike_1
```

### The Authoring Workflow

1. **Create effect template** (once per type)
   - `resources/effects/reaction_counter.tres`
   - Script: `Skill_Effect_Reaction`
   - `trigger = ON_DAMAGE_TAKEN`
   - `charges = 1` ← default, overridden per mnemonic

2. **Create payload mnemonic** (for reactions only)
   - `resources/mnemonics/counter_strike_1.tres`
   - `power = 20`
   - `damage_type = Pierce`

3. **Create stance mnemonic**
   - `resources/mnemonics/counter_stance.tres`
   - `mnemonic_name = "COUNTER"`
   - `ap_cost = 4`
   - `effect_steps = [reaction_counter]` ← references template
   - Override: `reaction_counter.charges = 3`
   - Override: `reaction_counter.payload_mnemonic = counter_strike_1`

**The mnemonic is a dumb container.** It doesn't know it's a reaction. It just knows: "I cost 4 AP and I apply this effect." The effect template knows it's a reaction grant. The payload mnemonic knows it's a damage effect. Composition all the way down.

### Why Reactions Are Abstracted

**The user's caveat:** "We abstract the reaction just cause its a special somewhat case, even tho it's just a conditional damage_effect/applytoken_effect."

**Honest assessment:** Reactions are abstracted for two reasons, neither of which is fundamental:

1. **Payload is external.** DoT, buff, and ailment tokens carry their behavior inline (formula, modifier, status type). Reaction tokens carry a `payload_mnemonic` reference. This requires a separate resource and a `TargetMode` enum for target resolution.

2. **Trigger conditions are complex.** DoT ticks every turn unconditionally. Reactions check `trigger_context.any_hit`, `trigger_context.source`, etc. This requires `check_trigger()` to read the primary action context.

**But conceptually?** Reactions are just token grants. The same family as DoT and buff. The abstraction exists because the payload is external, not because reactions are a different species.

**Future unification:** If we ever want buffs with external payloads (e.g., "grant a buff that executes a heal mnemonic"), the same `payload_mnemonic` pattern applies. The abstraction isn't reaction-specific — it's "token grant with external payload."

---

## Updated Architecture

### Components

| Component | Role |
|-----------|------|
| `MnemonicResource` | **Container.** Costs, description, targeting, array of effect template references |
| `Skill_Effect_Damage` | **Template.** "Create a Damage token, fire instantly" |
| `Skill_Effect_Healing` | **Template.** "Create a Heal token, fire instantly" |
| `Skill_Effect_DoT` | **Template.** "Create a DoT token, attach with N charges" |
| `Skill_Effect_Buff` | **Template.** "Create a Buff token, attach with N charges" |
| `Skill_Effect_Debuff` | **Template.** "Create a Debuff token, attach with N charges" |
| `Skill_Effect_Ailment` | **Template.** "Create an Ailment token, attach with N charges" |
| `Skill_Effect_Reaction` | **Template.** "Create a Reaction token, attach with N charges, payload = mnemonic" |
| `RuntimeToken` | **Base instance.** trigger, charges, source, owner |
| `RuntimeToken_Damage` | **Instance.** `fire()` calculates and applies damage |
| `RuntimeToken_DoT` | **Instance.** `tick()` applies DoT formula |
| `RuntimeToken_Reaction` | **Instance.** `fire()` executes `payload_mnemonic` via `SkillExecutor` |
| `SkillExecutor` | **Factory.** Reads mnemonic effect steps, creates correct tokens, fires instant ones, attaches persistent ones |
| `ActionPipeline` | **Orchestrator.** Announces, pre-pass, validates, executes primary, post-pass, emits resolved. Unchanged by this design |

### Token Trigger Enum

```gdscript
enum Trigger {
    INSTANT,           # Damage, Healing — fire now, discard
    ON_TURN_START,     # DoT, Buff, Debuff, Ailment, HoT — tick on owner's turn
    ON_DAMAGE_TAKEN,   # COUNTER, BRACE — fire when owner is hit
    ON_ALLY_HIT,       # VIGIL, FOLLOW UP — fire when ally is hit
    PRE_EXECUTION,     # HAMEDO, PREMONITION — fire before primary action
}
```

### Target Resolution Modes (for reactions)

```gdscript
enum TargetMode {
    SOURCE,      # Hit the one who initiated the primary action
    TARGET,      # Hit the primary target of the primary action
    OWNER,       # Target is self
    ALLY_HIT,    # The ally who was hit
}
```

### Execution Path

**Primary actions** go through `ActionPipeline.run()`:
1. Announce
2. PRE-pass (collect PRE_EXECUTION tokens)
3. Validate
4. SkillExecutor.execute(primary context)
5. POST-pass (collect ON_DAMAGE_TAKEN / ON_ALLY_HIT tokens)
6. Emit resolved

**Reactions** bypass the pipeline:
```gdscript
# Inside RuntimeToken_Reaction.fire()
var reaction_ctx := ActionContext.new()
reaction_ctx.source = owner
reaction_ctx.target = _resolve_target(trigger_context)
reaction_ctx.mnemonic = payload_mnemonic
SkillExecutor.execute(reaction_ctx)
```

No announce. No validation. No pre/post pass. Direct execution. Prevents chains.

---

## Design Decisions

### 1. Mnemonics Are Dumb Containers

A mnemonic does not know what it does. It only knows what it costs, what it targets, and which effect templates it references. The templates determine the behavior.

**Why:** Composability. FERVOR grants MOMENTUM + COUNTER with the same pattern as Viper Strike grants damage + poison. The container is just a delivery mechanism.

### 2. Effect Templates Are External Resources

Effect templates live as standalone `.tres` files in `resources/effects/`. Mnemonics reference them. Godot creates unique copies when fields are overridden.

**Why:** Reuse. `dot_poison.tres` is referenced by Viper Strike, Poison Jab, and any future poison skill. One template, many usages.

### 3. Charges Are Per-Mnemonic Override

The template defines a default charge count (usually 1). The mnemonic overrides it.

```gdscript
# dot_poison.tres default:
charges = 1

# Viper Strike overrides:
dot_poison.charges = 3

# Poison Jab overrides:
dot_poison.charges = 5
```

**Why:** The same template can create short or long-duration effects without duplicating files.

### 4. Reactions Use External Payloads

Reaction templates reference a `payload_mnemonic` — a separate mnemonic resource that defines the actual effect (damage, heal, buff).

**Why:** Power scaling. The payload mnemonic carries Power, damage type, crit chance — all the authored data. The reaction template just says "when triggered, execute this."

### 5. Payload Mnemonics Have Zero Cost

`COUNTER STRIKE` has AP=0, MP=0, HP%=0. The cost is paid on the stance (`COUNTER STANCE`, AP=4).

**Why:** The player already paid. Triggering the reaction is free. Costs on payload mnemonics are meaningless because they're never cast directly.

### 6. One Generic Reaction Token Class

No `RuntimeToken_Counter`, `RuntimeToken_Hamedo`, `RuntimeToken_Vigil`.

Just `RuntimeToken_Reaction` with:
- `trigger: Trigger`
- `payload_mnemonic: MnemonicResource`
- `target_mode: TargetMode`

**Why:** Data-driven. Behavior is determined by the payload, not the token class.

---

## Edge Cases

### Edge Case 1: Self-Reference

**Problem:** Reaction template references its own mnemonic as payload.

**Resolution:** Godot's resource system allows circular references, but it's brittle and confusing. Authoring guideline: "Payload mnemonics must be separate resources. Never self-reference."

### Edge Case 2: Payload Is Null

**Problem:** `payload_mnemonic` not set on reaction template.

**Resolution:** `SkillExecutor._create_reaction_token()` logs error and returns null. `RuntimeToken_Reaction.fire()` logs warning and returns. Never crash.

### Edge Case 3: Target Resolution Fails

**Problem:** `target_mode = SOURCE` but `trigger_context.source` is null.

**Resolution:** `_resolve_target()` returns null. `fire()` logs warning and returns. Graceful degradation.

### Edge Case 4: Reaction Token With Zero Charges

**Problem:** Token reaches 0 charges but isn't removed.

**Resolution:** `fire()` decrements charges. `ActiveTokens` removes at 0. `collect_triggers()` only iterates active tokens.

### Edge Case 5: Reaction Downs Last Enemy

**Problem:** Counter kills final enemy. Combat should end.

**Resolution:** `_check_combat_end()` runs at TURN_END. Not after every reaction. Combat ends cleanly at the end of the turn.

---

## What We Don't Build Yet

| Feature | Why Not Now |
|---------|-------------|
| Gear-granted tokens at combat start | Gear system is minimal; cast stances mid-combat |
| Reaction banners/animations | No animation system; floating numbers suffice |
| Reaction chain prevention | Direct SkillExecutor prevents chains by construction |
| Reaction priority/order | One reaction at a time; iterate in attachment order |
| Multi-step payloads | COUNTER STRIKE has one step for now |
| Buff/Debuff/Ailment templates | DoT and Reaction prove the pattern; extend later |
| PREMONITION nullification UI | Negated actions just log; no visual feedback yet |

---

## Files to Create/Modify

### New Files
- `scripts/combat/skills/effects/Skill_Effect_Reaction.gd`
- `scripts/combat/tokens/RuntimeToken_Reaction.gd`
- `resources/effects/reaction_counter.tres`
- `resources/effects/dot_poison.tres` (move from embedded)
- `resources/mnemonics/counter_stance.tres`
- `resources/mnemonics/counter_strike.tres`

### Modified Files
- `scripts/combat/SkillExecutor.gd` — add `_create_reaction_token()`, handle `Skill_Effect_Reaction`
- `scripts/combat/ActionContext.gd` — add `reaction_depth: int = 0` (optional insurance)
- `scripts/combat/tokens/RuntimeToken.gd` — add `TargetMode` enum
- `DOCS/GDD_V2.md` — add container-template-instance model, stance/payload separation
- `DOCS/Architecture.md` — update token system architecture

---

## The Bottom Line

**The entire combat system reduces to one pattern:**

> Container delivers templates. Templates become instances. Instances fire now or later.

- **Instant** (damage, heal) → fire now, discard
- **Persistent** (DoT, buff, debuff, ailment, reaction) → attach, fire later on trigger

**Reactions are not a separate system.** They are persistent tokens whose payload is external. The same factory (`SkillExecutor`), the same pipeline (`ActionPipeline`), the same token lifecycle (`ActiveTokens`).

**The user's insight — "the skill doesn't give a shit whether it's a reaction, buff or debuff" — is correct.** The mnemonic is a dumb container. The effect template determines the behavior. The token is the runtime instance. That's the whole architecture.

**The only new code:**
1. `Skill_Effect_Reaction` — "grant a reaction token"
2. `RuntimeToken_Reaction` — "when triggered, execute payload mnemonic"

Everything else is composition. Same factory, same pipeline, same tokens.

---

## Next Step

**Write an implementation plan.** One reaction end-to-end (COUNTER). Prove the pipeline. Then generalize.

**The pipeline is ready. The design is ready. Let's build it.**
