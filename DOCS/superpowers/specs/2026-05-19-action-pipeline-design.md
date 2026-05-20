# Action Pipeline — Design Spec
*2026-05-19*

## The Problem

`_enter_action_execution()` in CombatFSM is doing eight different jobs: AP/MP guard, context creation, announcement, presentation timing, skill execution, HP cost, downed detection, and combat-end check. It will grow worse the moment reactions are wired in. Left alone, this is how V1's god-manager was born.

The root cause: the FSM is acting as an orchestrator. It shouldn't be. An FSM should be a state pump — "done here, go there" — nothing else.

---

## The Core Insight

Tokens are already self-sufficient. Each token knows its trigger conditions, its target, and how to apply itself. The architecture should let tokens *declare themselves* rather than requiring a central system to know about every token type and dispatch them individually.

This gives us one rule that governs the whole system:

> **If context matches trigger → token queues itself. Everything runs through the same execution pipeline.**

---

## The Architecture

### Pieces

**CombatFSM** — pure state pump. Enters ACTION_EXECUTION, delegates to ActionPipeline, awaits one signal back (`pipeline_complete`), transitions to TURN_END. It never sees reactions. It never reads ActionContext fields.

**ActionContext** — the shared scratchpad and API. Created once per declared action. Holds everything tokens need to read (attacker, target, mnemonic, hit results, damage totals) and provides `record_step()` for tokens to write results back. Also holds the execution queue.

**CombatEvents** — the broadcaster. Gains one new signal: `action_context_ready(context: ActionContext)`. Fired by ActionPipeline at two moments: before execution (pre-pass) and after the primary action resolves (post-pass). Every armed token on the board receives it synchronously.

> **Constraint: `action_context_ready` is synchronous-only. No `await` inside any `check_trigger` handler, ever.** GDScript signal emission is synchronous — all connected listeners fire and return before the next line executes. ActionPipeline relies on this: it emits, the queue populates, then it drains. An `await` inside `check_trigger` breaks the ordering guarantee silently — the drain starts before the queue is fully built. This constraint belongs as a comment on the signal declaration in `CombatEvents.gd`.

**ActionPipeline** — a new Node under CombatScene. Manages the full execution lifecycle. Owns the queue. Emits `pipeline_complete` when done. The FSM delegates here; the FSM never touches the queue.

**RuntimeToken** — unchanged in base structure. The Trigger enum already names the reaction types. A token's `check_trigger(context)` method is the self-validation step: reads the context, returns true if conditions are met.

**ActiveTokens** — gains connect/disconnect lifecycle. When a reaction token (PRE_EXECUTION, ON_DAMAGE_TAKEN, ON_ALLY_HIT) is added to an actor, ActiveTokens connects it to `CombatEvents.action_context_ready`. When the token is removed, it disconnects. INSTANT and ON_TURN_START tokens are unchanged — they don't self-select.

---

## The Pipeline

```
FSM enters ACTION_EXECUTION
  → ActionPipeline.run(mnemonic, attacker, target)

ActionPipeline:
  1. Create ActionContext (attacker, target, mnemonic)
  2. Emit CombatEvents.action_context_ready(context)          ← PRE-PASS
     → Armed tokens receive it synchronously
     → Each token calls check_trigger(context)
     → PRE_EXECUTION tokens that match: append self to context queue (BEFORE primary)
  3. Append primary action to queue
  4. Drain queue:
     → Run each item via SkillExecutor
     → Results written into ActionContext via record_step()
  5. Emit CombatEvents.action_context_ready(context)          ← POST-PASS
     → Armed tokens receive updated context (any_hit, total_damage, etc.)
     → ON_DAMAGE_TAKEN, ON_ALLY_HIT tokens that match: append self to queue (AFTER primary)
     → One reaction per actor per window (consumed flag, reset each pipeline run)
  6. Drain post-queue
  7. Emit pipeline_complete

FSM receives pipeline_complete → transitions to TURN_END
TURN_END checks win/loss condition (not ActionPipeline's job)
```

---

## Token Self-Validation

Each reaction token implements `check_trigger(context: ActionContext) -> bool`:

```gdscript
# HAMEDO — "attack an enemy before they hit you, triggered by being the target of a melee skill"
func check_trigger(context: ActionContext) -> bool:
    return context.primary_target == owner and context.mnemonic.skill_type == SkillType.MELEE

# COUNTER — "strike back when you take a hit"
func check_trigger(context: ActionContext) -> bool:
    return context.primary_target == owner and context.any_hit

# VIGIL — "when an ally takes damage, heal them"
func check_trigger(context: ActionContext) -> bool:
    return context.primary_target != owner and context.primary_target.is_player_controlled == owner.is_player_controlled and context.any_hit
```

The token knows its own conditions. ActionPipeline doesn't. Adding a new reaction type means writing a new token — nothing else changes.

---

## Execution Queue Shape

```
[ PRE reactions (PULSE order) ]  →  [ primary action ]  →  [ POST reactions (PULSE order) ]
```

PRE reactions are queued during the pre-pass (before primary resolves).  
POST reactions are queued during the post-pass (after primary resolves, context has results).  
Reactions do not trigger further reactions — consumed flag prevents re-entry within the same window.

---

## What Changes From Current State

| Current | Proposed |
|---|---|
| `_enter_action_execution` does 8 things | Does 2: spend AP/MP, delegate to ActionPipeline |
| REACTION_SCAN is an FSM stub state | Dissolved into ActionPipeline (FSM goes directly ACTION_EXECUTION → TURN_END) |
| Downed check lives in FSM | Lives in TURN_END (where GDD placed it) |
| Combat end check scattered across states | Centralised in TURN_END |
| RuntimeToken.Trigger stubs unused | ON_DAMAGE_TAKEN, ON_ALLY_HIT, PRE_EXECUTION wired up |
| ActiveTokens only manages lifecycle | Also manages signal connect/disconnect for reaction tokens |

---

## What Does Not Change

- SkillExecutor — still the unified APPLY mechanism. Both primary actions and reactions run through it.
- ActionContext — extended (execution queue field, `trigger_context` reference for nested reaction contexts if needed later), not replaced.
- CombatFSM state sequence — TURN_START → ACTION_SELECT → ACTION_EXECUTION → TURN_END. REACTION_SCAN removed.
- ON_TURN_START token ticking — stays in `ActiveTokens.tick_turn_start()`, called by FSM at TURN_START. Unchanged.

---

## Open Questions (not blocking)

- **PULSE ordering within reaction tiers** — when multiple tokens queue themselves in the same pass, they should resolve in PULSE order. Needs the actor's PULSE stat accessible at queue time.
- **trigger_context for nested reactions** — if a POST reaction (COUNTER) needs to reference what triggered it, ActionContext gains a `trigger_context: ActionContext` field pointing to the original. Not needed until COUNTER is implemented.
- **AoE targeting** — when primary action hits multiple targets, which target does `context.primary_target` refer to? TargetingData spec resolves this separately.
