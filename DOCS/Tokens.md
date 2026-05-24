# NEVERWORLD — Token Reference

> Quick reference for all combat tokens — what they do, how they tick, and what's implemented.
> For system architecture see `Architecture.md`. For design intent see `GDD_V2.md`.

---

## Implemented

### Damage Tokens

| Token | Class | Trigger | Mechanic |
|-------|-------|---------|---------|
| **DAMAGE** | `RuntimeToken_Damage` | INSTANT | Standard attack. Hit roll (physical only), crit roll, resist multiplier, buff/debuff multiplier. `power` × AtkStat / (DefStat + 10) × variance. Logs `mult:` field when a multiplier is active. |
| **ENVENOM** | `RuntimeToken_Envenom` | INSTANT | Finisher — consumes all tokens of `consume_type` on target, deals `count × power_per_token` into the standard damage formula. Greyed in ActionMenu unless target holds the required token (`requires_token_on_enemy`). Scales to ENVENOM II+ by changing `power_per_token` in the blueprint `.tres`. |

### DoT Tokens

| Token | Class | Trigger | Tick Formula |
|-------|-------|---------|-------------|
| **POISON** | `RuntimeToken_Poison` | ON_TURN_START | `(max_hp × 10% + max_mp × 10%) × resist_multiplier` |

> BURN and BLEED blueprints exist (`resources/tokens/`) but tick logic is not yet wired.

### Buff / Debuff Tokens

Expire at **TurnEnd**. One instance consumed per turn. Cast turn is free for self-buffs (`skip_first_tick = true`).

| Token | Class | Trigger | Mechanic | Opposes |
|-------|-------|---------|---------|---------|
| **EMPOWER** | `RuntimeToken_Empower` | ON_TURN_END | ×1.5 damage multiplier. Read passively by `RuntimeToken_Damage` via `get_damage_multiplier()`. | WEAKEN |
| **WEAKEN** | `RuntimeToken_Weaken` | ON_TURN_END | ×0.75 damage multiplier. Same passive hook. | EMPOWER |

EMPOWER and WEAKEN can never coexist on the same actor — applying one cancels an instance of the other.

### CC Tokens

| Token | Class | Trigger | Mechanic |
|-------|-------|---------|---------|
| **STUN** | `RuntimeToken_Stun` | — | Consumed by `CombatFSM._enter_turn_start()` before AP gain. DoT/HoT ticks still fire. Turn skips straight to TURN_END. CT is consumed normally. |

### Reaction Tokens

Collected by ActionPipeline POST-pass. Fire after the primary action fully resolves.

| Token | Class | Trigger | Mechanic |
|-------|-------|---------|---------|
| **COUNTER** | `RuntimeToken_Counter` | ON_DAMAGE_TAKEN | Retaliates against the attacker with a damage hit. Only fires if the incoming action produced step results (guards against triggering on self-buffs). |
| **VIGIL** | `RuntimeToken_Vigil` | ON_ALLY_HIT | Heals a damaged ally. Triggers on any hit that dealt damage (`context.any_hit`), not on DoT/HoT ticks. One VIGIL instance per reaction event. |

---

## Planned

These tokens are specified in the GDD or design notes but have no implementation yet.

### DoT / HoT

| Token | Trigger | Tick Formula | Notes |
|-------|---------|-------------|-------|
| **BURN** | ON_TURN_START | `max_hp × 10% × resist_mult` | Fire type. +fire damage taken while active. Blueprint `.tres` exists. |
| **BLEED** | ON_TURN_START | `max_hp × 10% × resist_mult` | Feral type. Healing reduction while active. Blueprint `.tres` exists. |
| **REGEN** | ON_TURN_START | `max_hp × 10%` | HoT. Ticks on recipient's TurnStart. |
| **VIVIFY** | ON_TURN_START | `max_mp × 10%` | HoT. Restores MP per tick. |
| **REJUVENATE** | ON_TURN_START | `max_hp × 10% + max_mp × 10%` | HoT. Restores both. |

### Buffs / Debuffs

| Token | Trigger | Mechanic |
|-------|---------|---------|
| **MOMENTUM** | Passive / consumed on hit | +25% Phys.Atk per stack. Multiple stacks from multi-hit skills. All stacks consumed on next physical hit. |
| **KEEN** | Passive / consumed on hit | Guarantees crit on next physical hit. Applied by Stalk-type skills. |

### CC Ailments

| Token | Type | Mechanic |
|-------|------|---------|
| **FREEZE** | Water CC | Action loss or speed debuff. Chance-gated, resistance-blocked. |
| **PETRIFY** | Stone CC | Near-KO status — actor is functionally downed but revivable via different means than standard down. |

### Passive (inline during damage calc)

| Token | Mechanic |
|-------|---------|
| **BRACE / Shield** | Reduces incoming damage by a flat % when owner is hit. Checked inline in `RuntimeToken_Damage.fire()`, expires after use. |
| **COVER / INTERCEPT** | Redirects damage aimed at a protected ally to the token's owner instead. Checked inline before damage calc. Paired: owner holds COVERING, protected ally holds COVERED. |

### Reactions (PRE-pass)

| Token | Trigger | Mechanic |
|-------|---------|---------|
| **HAMEDO** | PRE_EXECUTION | Fires before the primary action resolves. Attacks the incoming attacker first — if they're downed, the action is cancelled with no resource cost. |
| **PREMONITION** | PRE_EXECUTION | Nullifies an incoming magical action. Sets `context.negated = true`. AP/MP are still spent by the attacker. |

### Reactions (POST-pass)

| Token | Trigger | Mechanic |
|-------|---------|---------|
| **FOLLOW UP** | ON_ALLY_HIT | Fires after an ally lands a hit on an enemy. Same POST window as VIGIL. |

---

## Authoring Notes

- All tokens extend `RuntimeToken` (Resource). Blueprint `.tres` files live in `resources/tokens/`.
- Mnemonics reference tokens via `Skill_Effect_Instant` (fires now) or `Skill_Effect_Grant` (adds to ActiveTokens).
- Quantity = duration. `amount = 3` in a `Skill_Effect_Grant` = 3 instances = 3 turns.
- Self-buff tokens set `skip_first_tick = true` in `_init()` so the cast turn doesn't eat a use.
- Finisher tokens set `requires_token_on_enemy` on the `MnemonicResource` to grey the skill when no target qualifies.
- ENVENOM II = same `RuntimeToken_Envenom` class, different `.tres` with higher `power_per_token`.
