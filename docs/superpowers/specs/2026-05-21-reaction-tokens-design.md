# NEVERWORLD — Reaction Architecture Design Log

> **Date:** 2026-05-21
> **Status:** Design crystallized, awaiting implementation plan
> **Scope:** The universal reaction system. Any trigger condition → any mnemonic payload. Covers damage, healing, buffs, debuffs, token grants, cleanses, and any future effect type.

---

## The Problem We Started With

We built an `ActionPipeline` with PRE/POST passes for reactions. The pipeline collects tokens via `ActiveTokens.collect_triggers()`, checks conditions via `RuntimeToken.check_trigger()`, and fires them via `RuntimeToken.fire()`.

**Then we tried to implement COUNTER and hit a wall.**

Our damage formula is:
```
damage = Power × AtkStat / (DefStat + 10) × Random(0.85, 1.0)
```

**Power** is hand-authored per `Skill_Effect_Damage` step. Every damage source in the game — Uskrav, Viper Strike, enemy claws — has a Power value on its mnemonic.

**Reaction tokens have no Power.** A COUNTER token is just a `RuntimeToken` with `Trigger.ON_DAMAGE_TAKEN`. It doesn't carry a `Skill_Effect_Damage` step. It doesn't have a mnemonic. So when it fires, what Power does it use?

This isn't a coding problem. It's a **design contradiction**: our entire damage system is built around authored mnemonics, but reactions aren't mnemonics.

---

## The Failed Attempts

### Attempt 1: Universal COUNTER Token with Hardcoded Power
```gdscript
class_name RuntimeToken_Counter
var power: int = 20
```
**Why it failed:** No progression. No tuning. UI shows "COUNTER ???". Every COUNTER in the game deals the same damage. The player can't inspect the Power because there's no authored source.

### Attempt 2: % Return Damage
```gdscript
var counter_damage: int = int(incoming_damage * 0.5)
```
**Why it failed:** Degenerate case. Boss has COUNTER ×1. Player pokes with a weak mage hit (2 damage), eats 1 back, token gone for free. Big hits become discouraged. Not tactical — solved.

### Attempt 3: Token Carries `payload_mnemonic` — The Breakthrough
The user's insight: **COUNTER is a mnemonic. Just like Uskrav.**

```
COUNTER (mnemonic, AP=4, HP%=0)
└── Skill_Effect_ReactionGrant
    trigger = ON_DAMAGE_TAKEN
    charges = 3
    payload_mnemonic = COUNTER STRIKE
```

The token is a **trigger wrapper**. The mnemonic is the **payload**.

**Why this works:**
- Power lives where it belongs: on the mnemonic, authored by designer
- Ranked progression: COUNTER I (Power=20), COUNTER II (Power=35), COUNTER III (Power=50)
- RESONANCE investment bumps rank, just like Uskrav
- Composable: FERVOR can grant COUNTER III tokens + MOMENTUM tokens in one skill

---

## The Self-Reference Trap (And Escape)

**The user's first instinct:** "COUNTER is a mnemonic. It grants COUNTER tokens. Those tokens execute... COUNTER itself."

**The problem:** If `COUNTER.tres` has two effect steps:
1. `ReactionGrant` → grant 3× COUNTER tokens
2. `Damage` → Power=20

Then when the player **casts** COUNTER, `SkillExecutor.execute()` runs step 1 (grant tokens) **and then step 2** (deal immediate damage to the target). So casting your counter-stance also stabs the enemy. That's wrong — setting a stance shouldn't deal damage.

**The fix: Separate resources.**

```
COUNTER STANCE (mnemonic, AP=4, HP%=0)
└── Skill_Effect_ReactionGrant
    trigger = ON_DAMAGE_TAKEN
    charges = 3
    payload_mnemonic = COUNTER STRIKE   ← points to DIFFERENT resource

COUNTER STRIKE (mnemonic, AP=0, HP%=0)
└── Skill_Effect_Damage
    power = 20
    damage_type = Pierce
```

- **COUNTER STANCE** is what the player casts. Costs AP. Grants tokens. Appears in the action menu.
- **COUNTER STRIKE** is what the token executes. Never cast directly. Has the Power.
- Both are authored separately. The stance references the strike as its payload.
- RESONANCE upgrades bump both: more charges on stance, more Power on strike.

**This is the price of composability.** One mnemonic cannot be both a buff and its own payload without the immediate-effect contradiction. Two resources is boring, but boring is exactly what this codebase needs.

---

## The Final Architecture

### Components

| Component | Role |
|-----------|------|
| `Skill_Effect_ReactionGrant` | New effect resource. Extends `Skill_Effect_Base`. Specifies: trigger enum, charges, payload_mnemonic reference, target_mode |
| `RuntimeToken_Reaction` | Generic reaction token. No subclasses for Counter/Vigil/Hamedo. Fields: `trigger`, `payload_mnemonic`, `target_mode` |
| `SkillExecutor` | Extended to create `RuntimeToken_Reaction` from `Skill_Effect_ReactionGrant`. Extended to execute payload mnemonics when tokens fire |
| ActionPipeline | **Unchanged.** PRE/POST pass already wired. Tokens collected, tokens fired. The pipeline doesn't know or care what the payload is |
| CombatUIFSM | **Unchanged.** COUNTER STANCE appears in action menu like any other skill. Player casts it. Token appears on card |

### Token Lifecycle

```
1. COMBAT START
   Character has COUNTER STANCE equipped
   (but NO tokens yet — stances are cast mid-combat)

2. PLAYER TURN
   Player selects COUNTER STANCE from action menu
   ActionPipeline runs:
     ├── SkillExecutor.execute()
     │     └── Skill_Effect_ReactionGrant
     │           └── RuntimeToken_Reaction created
     │                 trigger = ON_DAMAGE_TAKEN
     │                 charges = 3
     │                 payload_mnemonic = COUNTER STRIKE
     │                 target_mode = SOURCE
     │                 → added to character.tokens
     └── action_resolved emitted

3. ENEMY TURN — enemy hits player
   ActionPipeline runs the primary action:
     ├── PRE-PASS (empty)
     ├── VALIDATE
     ├── SkillExecutor.execute(primary)
     ├── POST-PASS
     │     └── collect_triggers(context, ON_DAMAGE_TAKEN)
     │           └── finds player's COUNTER token
     │                 check_trigger() → true (primary hit me)
     │                 → added to post_queue
     ├── Execute post_queue:
     │     └── token.fire(reaction_ctx)
     │           ├── resolve target via target_mode
     │           │     SOURCE → primary.source (the enemy)
     │           ├── build scratch ActionContext
     │           │     source = token.owner (the player)
     │           │     target = resolved target (the enemy)
     │           │     mnemonic = payload_mnemonic (COUNTER STRIKE)
     │           ├── SkillExecutor.execute(reaction_ctx)
     │           │     └── Skill_Effect_Damage(power=20)
     │           │           └── RuntimeToken_Damage created, fired, damage dealt
     │           └── token.charges -= 1 (now 2)
     └── action_resolved emitted

4. NEXT ENEMY HIT
   Same flow. Token has 2 charges. Fires again. Now 1 charge.

5. THIRD ENEMY HIT
   Token fires. Charges hit 0. Token removed from ActiveTokens.
   No more counters until player re-casts the stance.
```

### Target Resolution Modes

```gdscript
enum TargetMode {
    SOURCE,      # Hit the one who initiated the primary action
    TARGET,      # Hit the primary target of the primary action
    OWNER,       # Target is self (e.g. self-heal on trigger)
    ALLY_HIT,    # The ally who was hit (for ON_ALLY_HIT triggers)
}
```

| Reaction | Trigger | TargetMode |
|----------|---------|------------|
| COUNTER | ON_DAMAGE_TAKEN | SOURCE |
| HAMEDO | PRE_EXECUTION | SOURCE |
| VIGIL | ON_ALLY_HIT | TARGET |
| FOLLOW UP | ON_ALLY_HIT | SOURCE |

### Execution Path for Reactions

**Reactions call `SkillExecutor.execute()` directly. They bypass `ActionPipeline.run()`.**

Why:
- No announce banner. A counter is a quick strike, not a dramatic skill declaration.
- No pre-pass. If COUNTER triggered PREMONITION on the enemy, that would be a chain. The GDD says "one level deep."
- No validation. The reaction already passed `check_trigger()`. No AP/MP cost.
- No post-pass. If COUNTER hit triggered another COUNTER, that's a chain. We stop at one.

The reaction token's `fire()`:
```gdscript
func fire(context: ActionContext) -> void:
    var primary := context.trigger_context
    var resolved_target := _resolve_target(primary)
    
    var reaction_ctx := ActionContext.new()
    reaction_ctx.source = owner
    reaction_ctx.target = resolved_target
    reaction_ctx.mnemonic = payload_mnemonic
    
    SkillExecutor.execute(reaction_ctx)
    
    # Downed check — same as primary
    if resolved_target.vitals.is_downed():
        CombatEvents.actor_downed.emit(resolved_target)
```

---

## Design Decisions and Rationale

### 1. Stances Are Cast, Not Passive

Characters start combat with **zero** reaction tokens. They must spend a turn and AP to cast a stance.

**Why:** Tactical depth. "Do I attack now or set up COUNTER?" If counters were always-on, they'd be must-equips with no tempo cost. Making them active stances creates real decisions.

**Future:** Gear that grants tokens at combat start is a separate concern. Don't build it now.

### 2. Payload Mnemonics Have Zero Cost

COUNTER STRIKE has AP=0, MP=0, HP%=0. The cost is paid on the stance (COUNTER STANCE, AP=4).

**Why:** The player already paid. Triggering the reaction is free. This is identical to how buffs work in most RPGs — pay upfront, triggered effect is gratis.

**Authoring guideline:** "Payload mnemonics should have zero costs. Costs go on the stance."

### 3. One Generic Reaction Token Class

No `RuntimeToken_Counter`, `RuntimeToken_Hamedo`, `RuntimeToken_Vigil`.

Just `RuntimeToken_Reaction` with:
- `trigger: Trigger` (PRE_EXECUTION, ON_DAMAGE_TAKEN, ON_ALLY_HIT)
- `payload_mnemonic: MnemonicResource`
- `target_mode: TargetMode`

**Why:** The behavior is entirely data-driven. The token just reads its fields and calls SkillExecutor. No need for subclasses.

### 4. Reaction Execution Bypasses ActionPipeline

Direct `SkillExecutor.execute()`, no pipeline.

**Why:** Prevents infinite chains. The pipeline's POST-pass triggers reactions. If a reaction went through the pipeline, its POST-pass would trigger more reactions. One level deep is the rule.

**Belt-and-suspenders:** Add `reaction_depth: int` to ActionContext, cap at 1. Probably unnecessary since direct SkillExecutor prevents chains by construction, but cheap insurance.

### 5. Payloads Can Be Any Mnemonic

COUNTER STRIKE is just a mnemonic with a `Skill_Effect_Damage` step. But a payload could be:
- A heal (VIGIL heals the ally who took damage)
- A buff (HAMEDO grants the attacker a stun token)
- A multi-step skill (COUNTER STRIKE IV hits twice)

**Why:** This is the GDD's "trigger and payload are independent" principle. A DamagePayload is the same component whether it fires instantly or reactively.

---

## Edge Cases and Open Questions

### Edge Case 1: Reaction Token Downed During Execution

What if COUNTER fires, the counter-attack hits the enemy, and the enemy's PREMONITION token negates it? Or what if the enemy dies mid-reaction?

**Resolution:** The reaction's `SkillExecutor.execute()` runs to completion. Downed checks happen after each effect step (same as primary). If the target dies, remaining effect steps still run (unless we add a per-step downed check). This is consistent with primary execution.

### Edge Case 2: Reaction Damage Exceeds Target HP

Same as primary damage. `take_damage()` handles overkill. No special case.

### Edge Case 3: Multiple Reactions on Same Trigger

Player has COUNTER ×3 and BRACE ×1. Both are `ON_DAMAGE_TAKEN`. Enemy hits.

**Resolution:** Both are collected into `post_queue`. Both fire in iteration order. The pipeline doesn't prioritize. If order matters (e.g., BRACE reduces damage, COUNTER hits back), that's a design question for the future. For now, iterate in token-attachment order.

### Edge Case 4: Reaction Token With Zero Charges

Token has `charges = 0` somehow. `ActiveTokens.tick_turn_start()` doesn't decrement charges (that's for ON_TURN_START). But `check_trigger()` could be called.

**Resolution:** `ActiveTokens.collect_triggers()` only iterates `_tokens`. If a token has 0 charges, it should have been removed. Ensure `fire()` decrements and `ActiveTokens` removes at 0.

### Edge Case 5: Payload Mnemonic Is Null

`Skill_Effect_ReactionGrant` doesn't set `payload_mnemonic`. Token is created with null payload.

**Resolution:** `SkillExecutor._create_reaction_token()` should assert/Log.error if payload is null. Runtime check in `RuntimeToken_Reaction.fire()` logs and returns if null. Never crash.

### Edge Case 6: Target Resolution Fails

`target_mode = SOURCE` but `trigger_context.source` is null (shouldn't happen). `target_mode = ALLY_HIT` but no ally was hit.

**Resolution:** `_resolve_target()` returns null. `fire()` logs warning and returns without executing. Graceful degradation.

### Open Question 1: Reaction UI Presentation

Does the player see "Counter Strike!" banner when a reaction fires? Or just a floating damage number?

**Current thinking:** No banner. Just floating number. Reactions are quick strikes, not dramatic declarations. If we want banners later, we add a `CombatEvents.reaction_fired` signal and UI subscribes. Not in MVP.

### Open Question 2: Reaction Downed Check

After a reaction fires and deals damage, should `_check_combat_end()` run?

**Current thinking:** No. The pipeline's `_check_combat_end()` runs at TURN_END. If a reaction downs the last enemy, combat ends at TURN_END. Checking after every reaction is premature and would interrupt the flow. The GDD's "check at TURN_END" rule stands.

### Open Question 3: Reaction Tokens and DoT

Can a reaction token's payload be a DoT? E.g., COUNTER POISON: when hit, apply poison.

**Current thinking:** Yes. The payload is a mnemonic. If the mnemonic has `Skill_Effect_DoT` steps, they attach to the target like any DoT. This is emergent behavior — we don't need to design it, it just works.

### Open Question 4: Can Reactions Crit?

If COUNTER STRIKE has `crit_chance = 5`, the `RuntimeToken_Damage` will roll crit normally.

**Current thinking:** Yes. Reactions use the full damage pipeline. If the payload mnemonic has crit_chance, it rolls. This is consistent.

### Open Question 5: MOMENTUM and COUNTER

MOMENTUM: "+25% Phys.Atk on next physical hit."

If player has MOMENTUM ×2 and COUNTER triggers, does the counter get the buff?

**Current thinking:** MOMENTUM is a passive token checked by `RuntimeToken_Damage.fire()`. The counter's payload executes `Skill_Effect_Damage`, which creates `RuntimeToken_Damage`, which checks for MOMENTUM. So yes, the counter gets the buff. This is correct and emergent.

---

## Composability Examples

### FERVOR
```
FERVOR (mnemonic, AP=5)
├── Skill_Effect_Buff  ← grant 3× MOMENTUM tokens to all allies
│   token_type = MOMENTUM
│   charges = 1
├── Skill_Effect_ReactionGrant  ← grant 3× COUNTER III tokens to all allies
│   trigger = ON_DAMAGE_TAKEN
│   charges = 3
│   payload_mnemonic = COUNTER STRIKE III
```

### VIGIL
```
VIGIL STANCE (mnemonic, AP=4)
└── Skill_Effect_ReactionGrant
    trigger = ON_ALLY_HIT
    charges = 3
    payload_mnemonic = VIGIL HEAL

VIGIL HEAL (mnemonic, AP=0)
└── Skill_Effect_Healing
    heal_power = 25
    target_mode = TARGET  ← heals the ally who was hit
```

### HAMEDO
```
HAMEDO STANCE (mnemonic, AP=3)
└── Skill_Effect_ReactionGrant
    trigger = PRE_EXECUTION
    charges = 2
    payload_mnemonic = HAMEDO STRIKE

HAMEDO STRIKE (mnemonic, AP=0)
└── Skill_Effect_Damage
    power = 15
    damage_type = Pierce
    target_mode = SOURCE
```

---

## What We Don't Build Yet

| Feature | Why Not Now |
|---------|-------------|
| Gear-granted reactions at combat start | Gear system is minimal; stances are cast mid-combat for now |
| Reaction banners/animations | No animation system yet; floating numbers suffice for MVP |
| Reaction chain prevention (`reaction_depth`) | Direct SkillExecutor prevents chains by construction; add later if needed |
| Reaction priority/order | One reaction at a time; iterate in attachment order |
| Multiple payload steps | COUNTER STRIKE has one step for now; multi-step payloads work but aren't tested |
| PREMONITION nullification UI | Negated actions just log; no visual feedback yet |

---

## Files to Create/Modify

### New Files
- `scripts/combat/skills/effects/Skill_Effect_ReactionGrant.gd`
- `scripts/combat/tokens/RuntimeToken_Reaction.gd`
- `resources/mnemonics/counter_stance.tres`
- `resources/mnemonics/counter_strike.tres`
- `resources/mnemonics/vigil_stance.tres` (future)
- `resources/mnemonics/vigil_heal.tres` (future)

### Modified Files
- `scripts/combat/SkillExecutor.gd` — add `_create_reaction_token()`, handle `Skill_Effect_ReactionGrant`
- `scripts/combat/ActionContext.gd` — add `reaction_depth: int = 0` (optional, insurance)
- `scripts/combat/tokens/RuntimeToken.gd` — add `TargetMode` enum (if not already present)
- `DOCS/GDD_V2.md` — add stance/payload separation note
- `DOCS/Architecture.md` — update reaction architecture section

---

## The Bottom Line

**The reaction system is not a new system. It's the existing token system executing existing mnemonics on a deferred trigger.**

- Tokens already have triggers, charges, and fire methods
- Mnemonics already have effect steps with authored Power
- SkillExecutor already creates tokens and executes effects
- ActionPipeline already collects and fires reaction tokens

The only new code is:
1. `Skill_Effect_ReactionGrant` — "grant a token"
2. `RuntimeToken_Reaction` — "when triggered, execute a mnemonic"

Everything else is composition. That's the GDD principle: triggers and payloads are independent. A DamagePayload is the same component whether it fires instantly or reactively.

**The user's insight — "COUNTER is a mnemonic" — collapses the entire problem.** Reactions don't need a new damage formula. They use the same formula as everything else. The token is just a deferred execution trigger.

---

## Next Step Recommendation

**Write a formal implementation plan.** This document is the design. Now turn it into tasks:
1. Create `Skill_Effect_ReactionGrant`
2. Create `RuntimeToken_Reaction`
3. Extend `SkillExecutor`
4. Author COUNTER STANCE + COUNTER STRIKE `.tres`
5. Equip to test character
6. Run combat, verify counter fires

One reaction. End-to-end. Then generalize to HAMEDO, VIGIL, FOLLOW UP.

**The pipeline is ready. The design is ready. Let's build it.**
