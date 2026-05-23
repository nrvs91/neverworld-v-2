# NEVERWORLD — Token System V2

> **Date:** 2026-05-22
> **Status:** Design epiphany — architecture collapses to tokens
> **Scope:** Universal token model. All combat effects reduce to: container + token + charges.

---

## The Epiphany

**Everything is a token.**

Damage, heal, DoT, buff, debuff, ailment, reaction — all tokens. The only difference is whether the token fires **instantly** or **persists**.

| What the player sees | What actually happens |
|---------------------|----------------------|
| "Skugge uses Uskrav" | Create Damage token → fire immediately → discard |
| "Viper Strike poisons the wolf" | Create Poison token → attach to wolf → tick later |
| "Vargi sets COUNTER" | Create Counter token → attach to Vargi → fire when Vargi is hit |

**The mnemonic is a dumb container.** It holds costs, description, targeting, and a list of "grant this token." The token holds ALL the behavior. The token is the star.

---

## The Three Laws

### Law 1: All Effects Are Token Grants

There are only **three** effect classes:

```gdscript
Skill_Effect_Instant    # create token → fire now → discard
Skill_Effect_Grant     # create token → attach → fire later on trigger
Skill_Effect_Remove    # find tokens on target → remove them
```

No `Skill_Effect_Damage`. No `Skill_Effect_DoT`. No `Skill_Effect_Reaction`. No `Skill_Effect_Buff`. Those are **tokens**, not effects.

### Law 2: Tokens Are Resources

`RuntimeToken` changes from `RefCounted` to `Resource`.

```gdscript
class_name RuntimeToken
extends Resource  # ← changed from RefCounted

enum Trigger {
    INSTANT
    ON_TURN_START
    ON_DAMAGE_TAKEN
    ON_ALLY_HIT
    PRE_EXECUTION
}

var token_type: String = ""
var trigger: Trigger = Trigger.INSTANT
var charges: int = 1
var source: CombatCharacter = null
var owner: CombatCharacter = null

func fire(_context: ActionContext) -> void:
    pass

func tick(_context: ActionContext) -> void:
    pass

func check_trigger(_context: ActionContext) -> bool:
    return false
```

**Why Resource?** So the Godot inspector can export it. So we can save `.tres` token blueprints. So `Skill_Effect_Grant` can show a dropdown of token files.

### Law 3: The Token Carries the Behavior

The effect doesn't know what a token does. It just creates it. The token knows its own behavior.

```gdscript
# RuntimeToken_Damage.gd
class_name RuntimeToken_Damage
extends RuntimeToken

var power: int = 0
var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
var crit_chance: int = 5

func _init() -> void:
    trigger = Trigger.INSTANT
    token_type = "DAMAGE"

func fire(context: ActionContext) -> void:
    # calculate hit, crit, damage, apply it
    # same logic as today
```

```gdscript
# RuntimeToken_Counter.gd
class_name RuntimeToken_Counter
extends RuntimeToken

var payload_mnemonic: MnemonicResource = null
var target_mode: TargetMode = TargetMode.SOURCE

func _init() -> void:
    trigger = Trigger.ON_DAMAGE_TAKEN
    token_type = "COUNTER"

func check_trigger(context: ActionContext) -> bool:
    var primary := context.trigger_context
    return primary.any_hit and primary.target == owner

func fire(context: ActionContext) -> void:
    var target := _resolve_target(context.trigger_context)
    var reaction_ctx := ActionContext.new()
    reaction_ctx.source = owner
    reaction_ctx.target = target
    reaction_ctx.mnemonic = payload_mnemonic
    SkillExecutor.execute(reaction_ctx)
```

```gdscript
# RuntimeToken_Poison.gd
class_name RuntimeToken_Poison
extends RuntimeToken

var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Nature

func _init() -> void:
    trigger = Trigger.ON_TURN_START
    token_type = "POISON"

func tick(context: ActionContext) -> void:
    var resist_mult := CombatCalculator.resist_multiplier(
        owner.resistance_profile.get_state(damage_type))
    var raw := (owner.vitals.max_hp * 0.1 + owner.vitals.max_mp * 0.1) * resist_mult
    var damage := max(1, int(raw))
    owner.vitals.take_damage(damage)
    context.record_step(true, damage, false)
    CombatEvents.dot_ticked.emit(self, context)
```

**Each token is custom-tailored.** Designed. Authored. It knows its own trigger, its own formula, its own conditions.

---

## The Finite Token Library

The game needs ~20 token types. Not hundreds. Finite. Predictable.

```
resources/tokens/
  ├── damage_pierce.tres           ← RuntimeToken_Damage, power=0, damage_type=Pierce
  ├── damage_slash.tres            ← RuntimeToken_Damage, power=0, damage_type=Slash
  ├── damage_blunt.tres            ← RuntimeToken_Damage, power=0, damage_type=Blunt
  ├── damage_fire.tres             ← RuntimeToken_Damage, power=0, damage_type=Fire
  ├── heal_base.tres               ← RuntimeToken_Heal, heal_power=0
  ├── poison_base.tres             ← RuntimeToken_Poison, charges=1
  ├── burn_base.tres               ← RuntimeToken_Burn, charges=1
  ├── bleed_base.tres              ← RuntimeToken_Bleed, charges=1
  ├── empower_base.tres            ← RuntimeToken_Buff, buff_type=EMPOWER, modifier=1.5
  ├── keen_base.tres               ← RuntimeToken_Buff, buff_type=KEEN
  ├── slow_base.tres               ← RuntimeToken_Debuff, debuff_type=SLOW, modifier=0.5
  ├── weaken_base.tres             ← RuntimeToken_Debuff, debuff_type=WEAKEN, modifier=0.5
  ├── counter_1.tres               ← RuntimeToken_Counter, payload=counter_strike_1
  ├── counter_2.tres               ← RuntimeToken_Counter, payload=counter_strike_2
  ├── counter_3.tres               ← RuntimeToken_Counter, payload=counter_strike_3
  ├── vigil_1.tres                 ← RuntimeToken_Vigil, payload=vigil_heal_1
  ├── hamedo_1.tres                ← RuntimeToken_Hamedo, payload=hamedo_strike_1
  └── stun_base.tres               ← RuntimeToken_Ailment, ailment_type=STUN
```

**The only fields the designer changes are `power` and `charges`.** Everything else is fixed per token type. Damage type doesn't change for a Pierce token. The buff modifier doesn't change for Empower.

---

## The Authoring Workflow

### Step 1: Create Token Blueprint

```gdscript
# resources/tokens/counter_1.tres
# Script: RuntimeToken_Counter
# trigger = ON_DAMAGE_TAKEN
# token_type = "COUNTER"
# payload_mnemonic = counter_strike_1  ← points to payload mnemonic
# target_mode = SOURCE
# charges = 1  ← default, overridden per usage
```

### Step 2: Create Payload Mnemonic (for reactions only)

```gdscript
# resources/mnemonics/counter_strike_1.tres
# Script: MnemonicResource
# mnemonic_name = "COUNTER STRIKE I"
# ap_cost = 0
# mp_cost = 0
# hp_cost_percent = 0.0
# effect_steps = [damage_pierce]
#   damage_pierce.power = 20
```

### Step 3: Create Stance Mnemonic

```gdscript
# resources/mnemonics/counter_stance.tres
# Script: MnemonicResource
# mnemonic_name = "COUNTER"
# ap_cost = 4
# effect_steps = [Skill_Effect_Grant]
#   grant.token = counter_1   ← references token blueprint
#   grant.charges = 3         ← override: 3 charges per use
```

**The mnemonic is a dumb container.** It doesn't know it's a reaction. It just knows: "I cost 4 AP and I grant 3 charges of this token." The token blueprint knows it's a counter. The payload mnemonic knows it's a damage effect.

---

## The Collapsed Effect Classes

### Skill_Effect_Instant

```gdscript
class_name Skill_Effect_Instant
extends Skill_Effect_Base

@export var token: RuntimeToken
```

Used for: Damage, Healing, any effect that fires now and discards.

### Skill_Effect_Grant

```gdscript
class_name Skill_Effect_Grant
extends Skill_Effect_Base

@export var token: RuntimeToken
@export var charges: int = 1
```

Used for: DoT, Buff, Debuff, Ailment, Reaction, HoT — any effect that attaches a token.

### Skill_Effect_Remove

```gdscript
class_name Skill_Effect_Remove
extends Skill_Effect_Base

@export var token_type: String = ""   # remove all tokens of this type
@export var charges: int = -1         # -1 = remove all, otherwise remove N charges
```

Used for: Cleanse, Purge, Dispel.

---

## The Stupid Factory

```gdscript
class_name SkillExecutor

static func execute(context: ActionContext) -> void:
    for effect in context.mnemonic.effect_steps:
        if effect is Skill_Effect_Instant:
            _fire_instant(effect, context)
        elif effect is Skill_Effect_Grant:
            _grant_token(effect, context)
        elif effect is Skill_Effect_Remove:
            _remove_tokens(effect, context)

static func _fire_instant(effect: Skill_Effect_Instant, context: ActionContext) -> void:
    var token := effect.token.duplicate(true) as RuntimeToken
    token.source = context.source
    token.owner = context.target
    token.fire(context)

static func _grant_token(effect: Skill_Effect_Grant, context: ActionContext) -> void:
    var token := effect.token.duplicate(true) as RuntimeToken
    token.source = context.source
    token.owner = context.target
    token.charges = effect.charges
    context.target.tokens.add_token(token)
    context.tokens_applied.append(token)

static func _remove_tokens(effect: Skill_Effect_Remove, context: ActionContext) -> void:
    context.target.tokens.remove_by_type(effect.token_type, effect.charges)
```

**That's it.** 30 lines. One factory. Three paths.

---

## The Token Lifecycle

```
1. COMBAT START
   Characters have mnemonics equipped. No tokens exist yet.

2. PLAYER TURN — casts COUNTER STANCE (AP=4)
   SkillExecutor.execute():
     └── Skill_Effect_Grant
           ├── duplicate counter_1 token blueprint
           ├── source = player, owner = player
           ├── charges = 3
           └── attach to player.tokens
   Card shows: COUNTER×3

3. ENEMY TURN — enemy hits player
   ActionPipeline runs primary action:
     ├── SkillExecutor.execute(primary)
     ├── POST-PASS
     │     └── player.tokens.collect_triggers(ON_DAMAGE_TAKEN)
     │           └── finds COUNTER token
     │                 check_trigger() → true (primary hit me)
     │                 → added to post_queue
     ├── Execute post_queue:
     │     └── token.fire(reaction_ctx)
     │           ├── resolve target = primary.source (the enemy)
     │           ├── build reaction context
     │           ├── SkillExecutor.execute(payload_mnemonic = counter_strike_1)
     │           │     └── Skill_Effect_Instant
     │           │           └── RuntimeToken_Damage(power=20)
     │           │                 └── damage dealt
     │           └── token.charges -= 1 (now 2)
     └── action_resolved

4. NEXT ENEMY HIT
   Same flow. Token has 2 charges. Fires again. Now 1 charge.

5. THIRD ENEMY HIT
   Token fires. Charges hit 0. Token removed.
```

---

## Design Decisions

### 1. Tokens Are Resources (Not RefCounted)

`RuntimeToken` extends `Resource`. This lets the Godot inspector export token blueprints. The designer creates `.tres` token files and drags them into effect steps.

**Cost:** Token overhead slightly higher (Resource vs RefCounted). **Benefit:** Clean authoring UX, reusable blueprints, inspector dropdowns.

### 2. Token Blueprints Carry Defaults

`counter_1.tres` has `charges = 1` as default. The mnemonic overrides to `charges = 3`. The token blueprint is the **type**. The mnemonic is the **usage**.

### 3. Payload Mnemonics Are Separate

`COUNTER STRIKE` is a standalone mnemonic. It has zero cost. It is never cast directly. The reaction token executes it via `SkillExecutor.execute()`.

**Why:** Power scaling. The payload mnemonic carries Power, damage type, crit chance. The reaction token just holds a reference.

### 4. No Token Subclasses for Family Members

No `RuntimeToken_Counter`, `RuntimeToken_Vigil`, `RuntimeToken_Hamedo`. Just `RuntimeToken` with:
- `trigger` enum
- `token_type` string (for UI display)
- Custom fields per type (power, payload_mnemonic, buff_type, etc.)

**Why:** The trigger and behavior are data-driven. A Counter token and a Vigil token are the same class with different `payload_mnemonic` and `trigger`. No need for subclasses.

Wait — actually, the user said "each token is custom tailored." So we DO have subclasses? Let me re-read...

User said: "there is.. COUNTER token. there is a POISON token. MARK token. BURN token. STUN token. each is... destinct. each is custom tailored."

So yes, subclasses. `RuntimeToken_Damage`, `RuntimeToken_Poison`, `RuntimeToken_Counter`, etc. Each knows its own formula, trigger, and behavior.

But the effect class is universal: `Skill_Effect_Grant` just says "attach this token." The token subclass determines what happens.

This is consistent. Let me update the doc to reflect this.

---

## The Token Subclass Family

```gdscript
RuntimeToken (base)
  ├── RuntimeToken_Damage     # power, damage_type, crit_chance, fire()
  ├── RuntimeToken_Heal       # heal_power, fire()
  ├── RuntimeToken_Poison     # damage_type, tick()
  ├── RuntimeToken_Burn       # damage_type, tick()
  ├── RuntimeToken_Bleed      # damage_type, tick()
  ├── RuntimeToken_Counter    # payload_mnemonic, target_mode, check_trigger(), fire()
  ├── RuntimeToken_Vigil      # payload_mnemonic, target_mode, check_trigger(), fire()
  ├── RuntimeToken_Hamedo     # payload_mnemonic, target_mode, check_trigger(), fire()
  ├── RuntimeToken_Empower    # modifier, tick()
  ├── RuntimeToken_Keen       # tick()
  ├── RuntimeToken_Slow       # modifier, tick()
  ├── RuntimeToken_Weaken     # modifier, tick()
  ├── RuntimeToken_Stun       # ailment_type, tick()
  └── RuntimeToken_Freeze     # ailment_type, tick()
```

**Each is ~10-20 lines.** Custom tailored. Designed. Authored.

---

## Edge Cases

### Edge Case 1: Self-Reference

**Problem:** Reaction token's payload is the same mnemonic that granted it.

**Resolution:** Payload mnemonics must be separate. Never self-reference. Authoring guideline: "Stance grants token. Token executes payload. Payload is a different mnemonic."

### Edge Case 2: Payload Is Null

**Problem:** `payload_mnemonic` not set on reaction token.

**Resolution:** `RuntimeToken_Counter.fire()` logs error and returns. `SkillExecutor` never crashes.

### Edge Case 3: Target Resolution Fails

**Problem:** `target_mode = SOURCE` but `trigger_context.source` is null.

**Resolution:** `_resolve_target()` returns null. `fire()` logs warning and returns. Graceful degradation.

### Edge Case 4: Token With Zero Charges

**Problem:** Token reaches 0 charges but isn't removed.

**Resolution:** `fire()` and `tick()` decrement charges. `ActiveTokens` removes at 0. `collect_triggers()` only iterates active tokens.

### Edge Case 5: Reaction Downs Last Enemy

**Problem:** Counter kills final enemy. Combat should end.

**Resolution:** `_check_combat_end()` runs at TURN_END. Not after every reaction. Combat ends cleanly.

---

## What We Don't Build Yet

| Feature | Why Not Now |
|---------|-------------|
| Gear-granted tokens at combat start | Gear system is minimal; cast stances mid-combat |
| Reaction banners/animations | No animation system; floating numbers suffice |
| Reaction chain prevention | Direct SkillExecutor prevents chains by construction |
| Reaction priority/order | One reaction at a time; iterate in attachment order |
| Multi-step payloads | COUNTER STRIKE has one step for now |
| Buff/Debuff/Ailment subclasses | DoT and Reaction prove the pattern; extend later |
| PREMONITION nullification UI | Negated actions just log; no visual feedback yet |

---

## Files to Create/Modify

### New Files
- `scripts/combat/skills/effects/Skill_Effect_Instant.gd`
- `scripts/combat/skills/effects/Skill_Effect_Grant.gd`
- `scripts/combat/skills/effects/Skill_Effect_Remove.gd`
- `scripts/combat/tokens/RuntimeToken_Counter.gd`
- `scripts/combat/tokens/RuntimeToken_Vigil.gd`
- `scripts/combat/tokens/RuntimeToken_Hamedo.gd`
- `resources/tokens/damage_pierce.tres`
- `resources/tokens/counter_1.tres`
- `resources/tokens/poison_base.tres`
- `resources/mnemonics/counter_stance.tres`
- `resources/mnemonics/counter_strike_1.tres`

### Modified Files
- `scripts/combat/tokens/RuntimeToken.gd` — change from `RefCounted` to `Resource`
- `scripts/combat/SkillExecutor.gd` — collapse to 3-path factory (~30 lines)
- `scripts/combat/tokens/RuntimeToken_Damage.gd` — ensure `trigger = INSTANT`
- `scripts/combat/tokens/RuntimeToken_DoT.gd` — rename to `RuntimeToken_Poison`, `RuntimeToken_Burn`, etc.
- `DOCS/GDD_V2.md` — update skill construction section
- `DOCS/Architecture.md` — update token system architecture

---

## The Bottom Line

**The entire combat system reduces to:**

> Container (mnemonic) + Token blueprint + Charges

- **Instant** → fire now, discard
- **Grant** → attach, fire later on trigger
- **Remove** → find and delete

**The effect class is universal.** `Skill_Effect_Grant` doesn't know or care what token it's granting. The token subclass carries all behavior. The mnemonic is just a shell.

**The user's insight — "there is no Skill_Effect_Reaction, there is just a COUNTER token" — is the correct abstraction.** Reactions aren't a system. They're just tokens with `trigger = ON_DAMAGE_TAKEN`. Buffs aren't a system. They're tokens with `trigger = ON_TURN_START`. Damage isn't a system. It's a token with `trigger = INSTANT`.

**Everything is a token.**

---

## Next Step

**Write an implementation plan.** This document is the design. Now turn it into tasks:

1. Refactor `RuntimeToken` from `RefCounted` to `Resource`
2. Create `Skill_Effect_Instant`, `Skill_Effect_Grant`, `Skill_Effect_Remove`
3. Rewrite `SkillExecutor` as 3-path factory
4. Create `RuntimeToken_Counter`
5. Author COUNTER token blueprint + COUNTER STRIKE payload + COUNTER STANCE mnemonic
6. Run combat, verify counter fires

One reaction. End-to-end. Then generalize to Poison, Burn, Empower, etc.

**The pipeline is ready. The design is ready. Tokens are the star. Let's build it.**
