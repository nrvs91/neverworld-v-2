# Token System Architecture

> **Design session:** 2026-05-16
> **Status:** Approved — ready for implementation planning
> **Validation target:** Viper Strike (Pierce damage + POISON DoT on hit)

---

## Why This Exists

The skill system MVP (shipped 2026-05-15) uses a flat procedural executor: `SkillExecutor` resolves effects inline, writes results to `ActionContext`, and `CombatFSM` applies damage. This works for instant damage but has no model for persistent effects — DoTs, buffs, stances, reactions. Every new effect type would require new inline logic in SkillExecutor.

The GDD states that every combat effect is a token — including instant damage. This rewrite aligns the code with that model. The payoff: adding BURN, COUNTER, or MOMENTUM later means adding a new token subclass and a dispatch point. Nothing else changes.

The current math (`CombatCalculator`) is correct and stays. Only the orchestration changes.

---

## Design Pillars

- **Everything is a token.** A sword slash and a three-turn BURN are the same architecture. They differ in trigger and charge count, nothing else.
- **Tokens are self-resolving.** A token knows what it does. It calls `CombatCalculator` for math and `VitalsComponent` for mutation. The FSM is an orchestrator, not a resolver.
- **ActionContext is the shared resolution window.** During a single mnemonic execution, all tokens read from and write to the same scratchpad. When the window closes, the context is discarded.
- **Persistent tokens live in ActiveTokens.** Only tokens that survive past the current resolution window are stored. Instant tokens fire and are discarded.

---

## Scope

**In scope (this spec):**
- `RuntimeToken` base class
- `RuntimeToken_Damage` (trigger: INSTANT)
- `RuntimeToken_DoT` (trigger: ON_TURN_START)
- `Skill_Effect_DoT` resource type
- `ActionContext` — add `record_step()` method
- `ActiveTokens` — full implementation (storage, ticking, expiry, signals)
- `SkillExecutor` — rewrite as token factory
- `CombatFSM` — TurnStart ticking, ACTION_EXECUTION updated
- Token display — minimal text indicator on character cards
- Viper Strike mnemonic authored and verified end-to-end

**Explicitly deferred:**
- `ON_DAMAGE_TAKEN` trigger (COUNTER, BRACE) — documented as stub
- `ON_ALLY_HIT` trigger (VIGIL, FOLLOW UP) — documented as stub
- Buff/Debuff token types
- Ailment tokens (FREEZE, PETRIFY)
- HoT tokens
- Cleanse / Transfer / Convert effects
- Full icon-based token display

---

## Data Model

### RuntimeToken (base)

```gdscript
class_name RuntimeToken
extends RefCounted

enum Trigger {
    INSTANT,
    ON_TURN_START,
    ON_DAMAGE_TAKEN,  # stub — not dispatched yet
    ON_ALLY_HIT,      # stub — not dispatched yet
}

var token_type: String       # "DAMAGE", "POISON", "BURN", "BLEED"
var trigger: Trigger
var charges: int = 1
var source: CombatCharacter  # who created this token (attacker)
var owner: CombatCharacter   # who this token is attached to (target)
```

Two resolution methods — which one a subclass implements depends on its trigger:

- `fire(context: ActionContext)` — called by SkillExecutor for INSTANT tokens. Reads `context.any_hit` for chaining. Writes results via `context.record_step()`.
- `tick(context: ActionContext)` — called by `ActiveTokens.tick_turn_start()` for ON_TURN_START tokens. Context is freshly created per token by ActiveTokens. Writes results via `context.record_step()`. Broadcasts the context with `dot_ticked` so reactive tokens on other characters can read it.

### RuntimeToken_Damage

Trigger: INSTANT. Moves the existing `SkillExecutor._resolve_damage()` logic into `fire()`. Same math, same hit/miss/crit/resistance pipeline. Result written to context via `record_step()`.

Properties mirror `Skill_Effect_Damage`: `power`, `damage_type`, `crit_chance`, `chance_tier`, `inherit_from_weapon`, `true_strike`.

### RuntimeToken_DoT

Trigger: ON_TURN_START.

Properties:
- `dot_tag: String` — "POISON", "BURN", or "BLEED"
- `damage_type: ResistanceType.DamageType` — for resistance lookup
- Tick formula is fixed per dot_tag (not authored per-instance — see GDD):
  - POISON: `(owner.vitals.max_hp × 0.1 + owner.vitals.max_mp × 0.1) × resist_mult`
  - BURN: `owner.vitals.max_hp × 0.1 × resist_mult`
  - BLEED: `owner.vitals.max_hp × 0.1 × resist_mult`

`tick(context: ActionContext)` resolves: look up owner's resistance state for `damage_type`, apply `CombatCalculator.resist_multiplier()`. If `resist_mult == 0.0` (IMMUNE), return immediately — no damage, no broadcast, charges still decrement. Otherwise call `owner.vitals.take_damage()`, call `context.record_step(true, damage, false)`, emit `CombatEvents.dot_ticked(self, context)`.

`charges` is decremented by `ActiveTokens` after `tick()` returns. When charges reach zero, `ActiveTokens` removes the token and emits `token_removed`.

---

## Skill_Effect_DoT Resource

New effect resource type, alongside the existing `Skill_Effect_Damage`:

```gdscript
class_name Skill_Effect_DoT
extends Skill_Effect_Base

enum DotTag { POISON, BURN, BLEED }

@export var dot_tag: DotTag = DotTag.POISON
@export var charges: int = 3
```

Damage formula is determined by `dot_tag` at tick time — not authored per instance. The GDD fixes these formulas. `charges` is the number of ticks (turns) the DoT lasts.

`needs_previous_hit` and `true_strike` are inherited from `Skill_Effect_Base`. For Viper Strike, the POISON step has `needs_previous_hit = true` — the DoT only lands if the Pierce damage step hit.

DoTs always land if the skill hits — they have no application chance. This distinguishes them from Ailments (FREEZE, PETRIFY), which are chance-gated and resistance-blocked. Resistance scales DoT tick damage, not landing.

---

## ActionContext — Resolution Window

Full field list:

```
mnemonic          — what skill was used
attacker          — who's acting (team derivable via .is_player_controlled)
primary_target    — main target
step_results[]    — one entry per INSTANT step that fires: {hit, damage, is_crit}
tokens_applied[]  — RuntimeTokens that attached during this execution (persistent only)
total_damage      — sum of all landed instant hits
any_hit           — true only if an instant damaging step connected
any_crit          — true if any instant step critted
```

**The right paradigm: ActionContext exists because a token resolved — not because a mnemonic was declared.** This distinction matters for reactive tokens like BLOOD SCENT (a boss token that grants a free attack whenever a BLEED ticks on a player). Without a context produced by the tick, BLOOD SCENT would need bespoke plumbing. With one, it just listens to `dot_ticked(token, context)` and reads the same newspaper everything else does.

**`mnemonic`, `attacker`, `primary_target` are nullable.** For DoT tick contexts, these fields are `null` — the metadata lives on the `RuntimeToken` itself (`token.source`, `token.owner`, `token.dot_tag`). The context carries results only. Never read `context.mnemonic` from a DoT context.

**`any_hit` contract:** only ever set to `true` by `record_step()` when `hit = true`. Persistent token attachment does NOT set `any_hit`.

**Team membership is not stored.** Derive at read-time from `CombatCharacter.is_player_controlled`.

One method on ActionContext:

```gdscript
func record_step(hit: bool, damage: int, is_crit: bool) -> void:
    step_results.append({hit = hit, damage = damage, is_crit = is_crit})
    if hit:
        any_hit = true
        total_damage += damage
    if is_crit:
        any_crit = true
```

**Context lifecycle:**
- Mnemonic resolution: CombatFSM creates one context per skill use, passes it to SkillExecutor. INSTANT tokens call `fire(context)`. Persistent tokens append to `tokens_applied`.
- DoT ticking: `ActiveTokens.tick_turn_start()` creates one fresh context **per token**. Each token calls `tick(context)`, writes its result via `record_step()`, then the context is broadcast with the signal and discarded. No cross-contamination between a POISON tick and a BURN tick on the same actor.

---

## ActiveTokens — Full Implementation

```
ActiveTokens
  _tokens: Array[RuntimeToken]

  add_token(token)      → append, emit token_added
  tick_turn_start()     → fire all ON_TURN_START tokens, decrement charges, remove expired
  flush()               → clear all tokens on combat end
```

`tick_turn_start()` creates **one fresh ActionContext per token**. For each ON_TURN_START token: create context (mnemonic/attacker/primary_target = null), call `token.tick(context)`, decrement charges, collect expired tokens, remove and emit `token_removed`. Order follows token addition order (FIFO). PULSE ordering applies to multi-actor reaction resolution, not to a single actor's own token ticking.

Signals (already declared in stub, now used):
- `token_added(token: RuntimeToken)` — consumed by display
- `token_removed(token: RuntimeToken)` — consumed by display
- `token_updated` — reserved, not emitted in this MVP

---

## SkillExecutor — Rewrite as Factory

ActionContext is created by CombatFSM before SkillExecutor is called — this allows pre-execution reactions to write to it first (redirect target, set negated flag). SkillExecutor receives the context rather than creating it.

```
execute(mnemonic, context) → ActionContext:
  for each effect in mnemonic.effect_steps:
    if effect.needs_previous_hit and not context.any_hit:
      context.record_step(false, 0, false)
      continue
    token = _create_token(effect, attacker, target)
    if token.trigger == INSTANT:
      token.fire(context)        # writes to context via record_step()
    else:
      target.active_tokens.add_token(token)
      context.tokens_applied.append(token)  # does NOT touch any_hit
  return context
```

`_create_token()` maps effect resource types to token instances:
- `Skill_Effect_Damage` → `RuntimeToken_Damage` (sets source, owner, copies all fields, trigger=INSTANT)
- `Skill_Effect_DoT` → `RuntimeToken_DoT` (sets source, owner, dot_tag, charges, trigger=ON_TURN_START)

The existing `_resolve_damage()` and `_resolve_effect()` methods are removed — that logic lives in `RuntimeToken_Damage.fire()` now.

`CombatCalculator` is not touched.

---

## CombatFSM — Two Changes

### TURN_START

After granting AP to the active actor, before emitting `TurnStarted`:

```gdscript
_active_actor.active_tokens.tick_turn_start()
```

This fires all ON_TURN_START tokens (DoTs, HoTs, buff durations) on the actor whose turn is beginning. Expired tokens are removed automatically by ActiveTokens.

### ACTION_EXECUTION

The `SkillExecutor.execute()` call stays. The result application loop stays. The only change: persistent tokens are already attached to `target.active_tokens` inside SkillExecutor, so the FSM's loop only handles instant damage results.

Damage application reads `result.damage` and calls `target.vitals.take_damage()` — same as before.

---

## CombatEvents — New Signals

```gdscript
signal dot_ticked(token: RuntimeToken, context: ActionContext)
```

Emitted by `RuntimeToken_DoT.tick(context)` after `context.record_step()`. Carries everything: `token.owner`, `token.dot_tag`, `token.damage_type` are on the token; `context.total_damage`, `context.any_hit` are in the context. Consumed by the floating number system (`token.owner`, `context.total_damage`) and by any future reactive token that cares about DoT events (e.g. BLOOD SCENT checks `token.dot_tag == "BLEED"`). No bespoke signal parameters needed — the newspaper carries it all.

Existing signals (`action_executed`, `actor_downed`, `vitals_changed`) are unchanged.

---

## Token Display — Minimal MVP

A text label on each PlayerCard and EnemyCard showing active persistent token types and their remaining charges. Format: `POISON×3` or `BURN×2 POISON×1`.

Updated when `ActiveTokens` emits `token_added` or `token_removed`. No sprites or icons yet — that's a visual polish pass after the system is functional.

This is the minimum needed to confirm tokens are working during playtesting.

---

## Deferred Triggers (Documented Stubs)

These trigger types are known and designed — they are not implemented in this pass but are included here so the full architecture is visible.

**ON_DAMAGE_TAKEN** — fires when the owner takes damage. Used by: COUNTER (deal damage back), BRACE (reduce incoming damage on next hit). Dispatch point: CombatFSM ACTION_EXECUTION, after damage is applied to vitals, calls `target.active_tokens.tick_damage_taken(context)`.

**ON_ALLY_HIT** — fires when any ally takes damage. Used by: VIGIL (heal the ally), FOLLOW UP (strike the attacker). Dispatch point: CombatFSM ACTION_EXECUTION, after damage is applied, calls `tick_ally_hit(context)` on all other actors on the same team.

Both require adding a new `tick_*()` method to `ActiveTokens` and a new dispatch call in CombatFSM. The token data model and `RuntimeToken` base class do not change.

**PRE_EXECUTION** — same token model and `tick_*()` pattern as all other triggers. Just dispatched earlier: before SkillExecutor runs, not after. Not architecturally special — just queue position 1.

Used by:
- **PREMONITION** — target counters before the hit lands. Sets `context.attack_negated = true` to cancel SkillExecutor entirely, or fires its counter and lets the original attack still resolve — design decision deferred to reaction spec.
- **COVER** — a tank intercepts. Sets `context.primary_target = tank` so SkillExecutor runs against the tank instead. `context.intended_target` (future field) records who was originally aimed at for display ("Bjorn covers Skugge!").

Dispatch point in full ACTION_EXECUTION sequence:
```
1. CombatFSM creates ActionContext (mnemonic, attacker, pending_target)
2. target.active_tokens.tick_pre_execution(context)
3. for each ally of target: ally.active_tokens.tick_pre_execution(context)   ← COVER lives here
4. if context.attack_negated → skip to REACTION_SCAN
5. SkillExecutor.execute(context)
6. target.active_tokens.tick_damage_taken(context)
7. for each ally of target: ally.active_tokens.tick_ally_hit(context)
```

Note: ActionContext must be created in CombatFSM *before* calling SkillExecutor so pre-execution tokens can write to it. SkillExecutor receives the already-created context rather than creating its own.

---

## Validation Target: Viper Strike

A two-step mnemonic that confirms the entire system works:

**Step 1 — Pierce damage:**
- `Skill_Effect_Damage`: power=25, damage_type=Pierce, inherit_from_weapon=false (viper fangs, not a weapon), chance_tier=HIGH, crit_chance=5, needs_previous_hit=false

**Step 2 — Poison on hit:**
- `Skill_Effect_DoT`: dot_tag=POISON, charges=3, needs_previous_hit=true

**What to verify:**
1. If Step 1 hits — POISON attaches to target's ActiveTokens, shows on card
2. If Step 1 misses — POISON does NOT attach (needs_previous_hit respected)
3. On each of target's next 3 TurnStarts — POISON ticks, damage number appears, charges count down
4. After 3 ticks — token expires, removed from display
5. Full pipeline unchanged for existing mnemonics (Skugge's Tergo Lupi, enemy Strike)

---

## File Map

**Create:**
- `scripts/combat/tokens/RuntimeToken.gd`
- `scripts/combat/tokens/RuntimeToken_Damage.gd`
- `scripts/combat/tokens/RuntimeToken_DoT.gd`
- `scripts/combat/skills/effects/Skill_Effect_DoT.gd`
- `resources/mnemonics/viper_strike/` (new folder — .tres files authored in editor)

**Modify:**
- `scripts/combat/ActionContext.gd` — add `record_step()`
- `scripts/combat/ActiveTokens.gd` — full implementation
- `scripts/combat/SkillExecutor.gd` — rewrite as factory
- `scripts/combat/CombatFSM.gd` — TurnStart ticking + ACTION_EXECUTION update
- `scripts/combat/CombatEvents.gd` — add `dot_ticked` signal
- `scenes/combat/ui/player_card.tscn` + `scripts/combat/ui/PlayerCard.gd` — token display label
- `scenes/combat/ui/enemy_card.tscn` + `scripts/combat/ui/EnemyCard.gd` — token display label
