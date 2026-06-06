# AP System Pivot — 2026-06-04

## Previous State: Parity AP

All combatants (player and enemy) had AP. Started at 3, gained +1 per turn, carried over, cap 10. Every skill cost AP. Enemies needed authored AP budgets, fallback skills, and AI that weighed spend vs. save.

**Problems:**
- Two-sided balance equation — every new mnemonic or enemy shifted the equilibrium
- Enemy AI authoring burden scaled poorly (20+ enemies × AP budgets × spend/save logic)
- PULSE compounded — high-PULSE characters got more turns AND more AP income
- STUN was overloaded — skip action AND deny AP gain, creating resource snowballs
- AP and tokens ran as parallel systems with no interaction

## What Changed

Pivoted to **player-exclusive, action-generated AP.** Only player characters have AP. Enemies run on patterns and cooldowns. AP is earned through actions, not passive turn income.

**Why:**
- Halves the balance problem (one-sided economy)
- Enemy authoring becomes trivial (no AP budgets, no fallback skills, no spend/save AI)
- Unifies token and action economies — generators build AP while applying tokens, consumers cash out both
- STUN becomes proportional (skip action only, no AP denial)
- PULSE rewards without breaking (more turns = faster engine, not compound advantage)

## What Is Now

### AP Economy

- **Player-exclusive:** only party members have AP bars
- **Action-generated:** no passive income, earned by using generator mnemonics
- **Cap:** 10, universal
- **Resets:** every encounter (clean slate, no farming)
- **Starting AP:** 0 (flagged for playtesting), gear can grant starting AP

### Mnemonic Roles

| Role | AP Effect | Example |
|------|-----------|---------|
| Generator | +1 to +2 AP | Uskrav, Viper Strike (deal damage + generate AP) |
| Neutral | 0 AP | Empower, Weaken (standalone utility) |
| Consumer | -2 to -4 AP | Strong attacks, detonators |
| Finisher | -5 to -9 AP | Fight-changing nukes |
| Hybrid | costs AP, refunds on condition | Envenom (costs 3 AP, -2 per POISON on target) |

### Basic Attack

Every character always has access to a basic attack (inherent action, not a mnemonic slot). Generates +1 AP, deals low Power damage, weapon damage type. Intentionally weak — an AP floor, not a combat tool. Mnemonics and gear can modify it (passives that add AP on crit, multi-hit, token application).

### Token-AP Interaction

Tokens modify AP costs and generation:
- **ap_reduction_conditions:** Dictionary on mnemonic. `{"POISON": 2}` means each POISON on target reduces AP cost by 2.
- **ap_generation_bonuses:** Dictionary on mnemonic. `{"SHIELD": 1}` means each SHIELD destroyed grants +1 bonus AP.
- **Token-level modifiers:** ALACRITY grants +1 AP per turn (universal board-state effect).

### Enemy Design

Enemies do not use AP. Behavior driven by patterns:
- Cooldown (skill available every N turns)
- HP Threshold (triggers at specific HP boundaries)
- Sequence (fixed rotation)
- Weighted Random (skill weights, no condition tracking)

Trash enemies: invisible patterns (learn through observation). Bosses: may telegraph with flavour text before big moves.

## Files Changed

### Code (10 files)

| File | Change |
|------|--------|
| `scripts/combat/skills/MnemonicResource.gd` | Added `ap_generates`, `ap_generation_bonuses`, `ap_reduction_conditions` fields. Changed `ap_cost` default from 1 to 0. |
| `scripts/combat/VitalsComponent.gd` | Start AP at 0 instead of 3 (setup and reset). |
| `scripts/combat/CombatFSM.gd` | Removed passive `gain_ap(1)` from TurnStart. |
| `scripts/combat/ActionPipeline.gd` | Added effective AP cost calculation with reduction conditions. Added AP generation after execution. Updated validation to use effective cost. |
| `scripts/combat/ActionContext.gd` | Added `token_snapshot` field for pre-execution token state. |
| `scripts/combat/ActiveTokens.gd` | Added `get_tokens()` public accessor for token snapshotting. |
| `scripts/combat/CombatCharacter.gd` | Inject basic attack mnemonic at index 0 for all characters. |
| `scripts/combat/ui/SkillButton.gd` | Display "+N AP" for generators, "N AP" for consumers, hidden for neutral. Updated affordability check. |
| `scripts/combat/ui/EnemyCard.gd` | Hide AP bar for enemies. |
| `resources/mnemonics/basic_attack/basic_attack.tres` | New file — basic attack mnemonic (generates +1 AP, Power 10). |

### Data (5 .tres files)

| File | Change |
|------|--------|
| `resources/mnemonics/uskrav/uskrav_tergo_lupi.tres` | Added `ap_generates = 1` |
| `resources/mnemonics/viper_strike/viper_strike.tres` | Added `ap_generates = 1` |
| `resources/mnemonics/envenom/envenom.tres` | Added `ap_cost = 3`, `ap_reduction_conditions = {"POISON": 2}` |
| `resources/mnemonics/stun_strike/stun_strike.tres` | Added `ap_cost = 1` |
| `resources/mnemonics/strike/enemy_basic_strike.tres` | Added `ap_generates = 0` |

### Documentation

| File | Change |
|------|--------|
| `DOCS/GDD_V2.md` | Rewrote AP Economy, Skill Costs, Basic Attack sections. Updated mnemonic construction diagram, Uskrav chain example, STUN description, Enemy AI section. |

## Commits

```
dee3d8f fix: format AP log line to respect Log.info 3-arg limit
2991b87 fix: cast BasicAttack.duplicate() to MnemonicRes for typed array
03c40b1 fix: build typed Array[MnemonicRes] without + operator to preserve element type
47ad999 feat: update mnemonic AP values for player-exclusive economy
6f68055 feat: update SkillButton for generator/consumer AP display
9fe4ee3 feat: effective AP cost with reduction conditions, AP generation after execution
f4b0d0a feat: inject basic attack mnemonic at index 0 for all combat characters
37c6583 feat: add basic attack mnemonic (generates +1 AP, Power 10)
0f90526 feat: start AP at 0, remove passive AP gain, hide enemy AP bar
7024789 feat: add ap_generates, ap_generation_bonuses, ap_reduction_conditions to MnemonicResource
```

## What's Next

Enemy design becomes the load-bearing pillar. Patterns need to be good enough that repetition doesn't breed contempt. Bosses need genuine threat without an AP economy to generate it. The system is simpler, but enemy variety must carry the combat loop alone.
