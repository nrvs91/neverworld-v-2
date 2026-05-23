# Token System V2 — Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the effect layer to three universal classes (Instant, Grant, Remove) with all behavior living in self-contained, single-use token subclasses.

**Architecture:** `RuntimeToken` changes base from `RefCounted` to `Resource` so token subclasses can be authored as `.tres` blueprints. Effect classes collapse from per-type (`Skill_Effect_Damage`, `Skill_Effect_DoT`) to per-timing (`Skill_Effect_Instant`, `Skill_Effect_Grant`, `Skill_Effect_Remove`). `ActiveTokens` drops charge-stacking: tokens are single-use instances, and only **one token per type fires per trigger event**. The one that fires is removed.

**Tech Stack:** Godot 4.6, GDScript, `.tres` resource files, Godot MCP

---

## Mental Model

- **Token** = one-shot behavior unit. No charges. Fires once, dies.
- **3 POISON** = 3 separate `RuntimeToken_Poison` instances on the character. One fires per `ON_TURN_START`, then is removed. Duration comes from quantity, not an internal counter.
- **Skill_Effect_Instant** = create token → fire now → discard (damage, heal)
- **Skill_Effect_Grant** = create N tokens → attach to character → fire later on trigger (DoT, reaction stances)
- **Skill_Effect_Remove** = remove all tokens of a given type (cleanse)

---

## File Map

### Modified
- `scripts/combat/tokens/RuntimeToken.gd` — change `extends RefCounted` → `extends Resource`, remove `charges` field
- `scripts/combat/tokens/RuntimeToken_Damage.gd` — add `@export` to all fields for inspector authoring
- `scripts/combat/skills/effects/Skill_Effect_Base.gd` — remove `@export var chance_tier` and `@export var true_strike` (now live on tokens); keep `ChanceTier` enum and `needs_previous_hit`
- `scripts/combat/ActiveTokens.gd` — drop charge-stacking in `add_token`, rewrite `tick_turn_start` for one-per-type, rewrite `get_display_text` to count instances, add `remove_token`
- `scripts/combat/SkillExecutor.gd` — rewrite as 3-path factory (~30 lines)
- `scripts/combat/ActionPipeline.gd` — call `remove_token` on each reaction token after it fires
- `resources/mnemonics/enemy_basic_strike.tres` — migrate to `Skill_Effect_Instant`
- `resources/mnemonics/uskrav_tergo_lupi.tres` — migrate to `Skill_Effect_Instant`
- `resources/mnemonics/viper_strike.tres` — migrate to `Skill_Effect_Instant` + `Skill_Effect_Grant`
- `resources/mnemonics/effect_blunt_15.tres` — migrate to `Skill_Effect_Instant`
- `resources/mnemonics/effect_slash_30.tres` — migrate to `Skill_Effect_Instant`

### Created
- `scripts/combat/tokens/RuntimeToken_Poison.gd`
- `scripts/combat/tokens/RuntimeToken_Burn.gd`
- `scripts/combat/tokens/RuntimeToken_Bleed.gd`
- `scripts/combat/skills/effects/Skill_Effect_Instant.gd`
- `scripts/combat/skills/effects/Skill_Effect_Grant.gd`
- `scripts/combat/skills/effects/Skill_Effect_Remove.gd`
- `resources/tokens/poison_base.tres`
- `resources/tokens/burn_base.tres`
- `resources/tokens/bleed_base.tres`

### Deleted
- `scripts/combat/tokens/RuntimeToken_DoT.gd`
- `scripts/combat/skills/effects/Skill_Effect_Damage.gd`
- `scripts/combat/skills/effects/Skill_Effect_DoT.gd`

---

## Task 1: RuntimeToken → Resource + ActiveTokens rewrite

> ⚠️ These two files must change together. Removing `charges` from `RuntimeToken` breaks `ActiveTokens` compilation until it's updated.

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken.gd`
- Modify: `scripts/combat/ActiveTokens.gd`

- [ ] **Step 1: Update RuntimeToken base class and remove charges**

Replace the entire file:

```gdscript
class_name RuntimeToken
extends Resource

enum Trigger {
	INSTANT,
	ON_TURN_START,
	ON_DAMAGE_TAKEN,  # stub — not dispatched yet (COUNTER, BRACE)
	ON_ALLY_HIT,      # stub — not dispatched yet (VIGIL, FOLLOW UP)
	PRE_EXECUTION,    # stub — not dispatched yet (PREMONITION, COVER)
}

var token_type: String = ""
var trigger: Trigger = Trigger.INSTANT
var source: CombatCharacter = null
var owner: CombatCharacter = null

func fire(_context: ActionContext) -> void:
	pass

func tick(_context: ActionContext) -> void:
	pass

func check_trigger(_context: ActionContext) -> bool:
	return false
```

- [ ] **Step 2: Rewrite ActiveTokens**

Replace the entire file:

```gdscript
class_name ActiveTokens
extends Node

const RuntimeToken = preload("res://scripts/combat/tokens/RuntimeToken.gd")
const ActionContext = preload("res://scripts/combat/ActionContext.gd")

signal token_added(token: RuntimeToken)
signal token_removed(token: RuntimeToken)

var _tokens: Array[RuntimeToken] = []

## Append one token instance. No stacking — multiple tokens of the same type are allowed.
func add_token(token: RuntimeToken) -> void:
	_tokens.append(token)
	Log.info("ActiveTokens — added", "%s %s" % [token.owner.character_name, token.token_type])
	token_added.emit(token)

## Remove a specific token instance (called after it fires or expires).
func remove_token(token: RuntimeToken) -> void:
	_tokens.erase(token)
	Log.info("ActiveTokens — consumed", "%s %s" % [token.owner.character_name, token.token_type])
	token_removed.emit(token)

## Fire ONE token per type with ON_TURN_START trigger, then remove it.
## One fresh ActionContext per token — no cross-contamination between ticks.
## Called by CombatFSM at the start of the active actor's turn.
func tick_turn_start() -> void:
	var fired_types: Array[String] = []
	var to_tick: Array[RuntimeToken] = []

	for token in _tokens:
		if token.trigger != RuntimeToken.Trigger.ON_TURN_START:
			continue
		if token.token_type in fired_types:
			continue
		fired_types.append(token.token_type)
		to_tick.append(token)

	for token in to_tick:
		var ctx := ActionContext.new()
		token.tick(ctx)
		_tokens.erase(token)
		Log.info("ActiveTokens — expired", "%s %s" % [token.owner.character_name, token.token_type])
		token_removed.emit(token)

## Returns display string for card UI. Counts instances per type. Format: "POISON×3 BURN×1"
func get_display_text() -> String:
	if _tokens.is_empty():
		return ""
	var counts: Dictionary = {}
	for token in _tokens:
		counts[token.token_type] = counts.get(token.token_type, 0) + 1
	var parts: Array = []
	for type_name in counts:
		parts.append("%s×%d" % [type_name, counts[type_name]])
	return " ".join(parts)

## Returns ONE token per type whose trigger matches and whose check_trigger passes.
## Only one fires per trigger event — multiple instances of same type queue for future events.
func collect_triggers(context: ActionContext, trigger: RuntimeToken.Trigger) -> Array:
	var result: Array = []
	var seen_types: Array[String] = []
	for token in _tokens:
		if token.trigger != trigger:
			continue
		if token.token_type in seen_types:
			continue
		if token.check_trigger(context):
			result.append(token)
			seen_types.append(token.token_type)
	return result

func flush() -> void:
	_tokens.clear()
	Log.info("ActiveTokens flushed")
```

- [ ] **Step 3: Validate in Godot**

Open Godot. Check the bottom panel for script errors. There should be none. The game should run — combat should still work (VIPER STRIKE's DoT ticking behavior will change in later tasks, but nothing crashes).

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken.gd scripts/combat/ActiveTokens.gd
git commit -m "refactor: RuntimeToken extends Resource, ActiveTokens uses single-use token instances"
```

---

## Task 2: New DoT token subclasses

Replace the single `RuntimeToken_DoT` (one class with a `dot_tag` match) with three separate, custom-tailored subclasses. Each knows its own formula.

**Files:**
- Create: `scripts/combat/tokens/RuntimeToken_Poison.gd`
- Create: `scripts/combat/tokens/RuntimeToken_Burn.gd`
- Create: `scripts/combat/tokens/RuntimeToken_Bleed.gd`

- [ ] **Step 1: Create RuntimeToken_Poison.gd**

```gdscript
class_name RuntimeToken_Poison
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_START
	token_type = "POISON"

## GDD formula: (max_hp × 10% + max_mp × 10%) × resistance multiplier
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(ResistanceType.DamageType.Nature)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	if resist_mult == 0.0:
		Log.info("RuntimeToken_Poison — IMMUNE", owner.character_name)
		return

	var damage: int = max(1, int((owner.vitals.max_hp * 0.1 + owner.vitals.max_mp * 0.1) * resist_mult))
	Log.info("RuntimeToken_Poison tick", "%s %d dmg" % [owner.character_name, damage])
	owner.vitals.take_damage(damage)
	context.record_step(true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
```

- [ ] **Step 2: Create RuntimeToken_Burn.gd**

```gdscript
class_name RuntimeToken_Burn
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_START
	token_type = "BURN"

## GDD formula: max_hp × 10% × resistance multiplier
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(ResistanceType.DamageType.Fire)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	if resist_mult == 0.0:
		Log.info("RuntimeToken_Burn — IMMUNE", owner.character_name)
		return

	var damage: int = max(1, int(owner.vitals.max_hp * 0.1 * resist_mult))
	Log.info("RuntimeToken_Burn tick", "%s %d dmg" % [owner.character_name, damage])
	owner.vitals.take_damage(damage)
	context.record_step(true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
```

- [ ] **Step 3: Create RuntimeToken_Bleed.gd**

```gdscript
class_name RuntimeToken_Bleed
extends RuntimeToken

func _init() -> void:
	trigger = Trigger.ON_TURN_START
	token_type = "BLEED"

## GDD formula: max_hp × 10% × resistance multiplier
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(ResistanceType.DamageType.Bleed)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	if resist_mult == 0.0:
		Log.info("RuntimeToken_Bleed — IMMUNE", owner.character_name)
		return

	var damage: int = max(1, int(owner.vitals.max_hp * 0.1 * resist_mult))
	Log.info("RuntimeToken_Bleed tick", "%s %d dmg" % [owner.character_name, damage])
	owner.vitals.take_damage(damage)
	context.record_step(true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
```

- [ ] **Step 4: Validate in Godot**

Check for parse errors. No crashes expected.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Poison.gd scripts/combat/tokens/RuntimeToken_Burn.gd scripts/combat/tokens/RuntimeToken_Bleed.gd
git commit -m "feat: add RuntimeToken_Poison, RuntimeToken_Burn, RuntimeToken_Bleed — distinct per-type DoT subclasses"
```

---

## Task 3: Make RuntimeToken_Damage inspector-ready

Damage token fields need `@export` so they're editable in the Godot inspector when authored inside a `Skill_Effect_Instant`.

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Damage.gd`

- [ ] **Step 1: Add @export to all fields**

Replace the field declarations (lines 6–11) — keep `_init`, `fire`, and helpers unchanged:

```gdscript
class_name RuntimeToken_Damage
extends RuntimeToken

const ActionContext = preload("res://scripts/combat/ActionContext.gd")

@export var power: int = 10
@export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
@export var crit_chance: int = 5
@export var chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH
@export var inherit_from_weapon: bool = true
@export var true_strike: bool = false
```

Leave everything below (`_init`, `fire`, `_is_physical`, `_get_weapon_damage_type`) exactly as-is.

- [ ] **Step 2: Validate in Godot**

No errors expected. Behavior is identical — only the export annotations changed.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Damage.gd
git commit -m "refactor: add @export to RuntimeToken_Damage fields for inspector authoring"
```

---

## Task 4: New effect classes + Skill_Effect_Base cleanup

Create the three universal effect classes. Clean up `Skill_Effect_Base` — it keeps the `ChanceTier` enum (still needed by `CombatCalculator` and `RuntimeToken_Damage`) but drops the exported `chance_tier` and `true_strike` fields (those now live on tokens).

**Files:**
- Create: `scripts/combat/skills/effects/Skill_Effect_Instant.gd`
- Create: `scripts/combat/skills/effects/Skill_Effect_Grant.gd`
- Create: `scripts/combat/skills/effects/Skill_Effect_Remove.gd`
- Modify: `scripts/combat/skills/effects/Skill_Effect_Base.gd`

- [ ] **Step 1: Create Skill_Effect_Instant.gd**

```gdscript
class_name Skill_Effect_Instant
extends Skill_Effect_Base

## Token blueprint to fire immediately. Duplicate + fire + discard. Never attached to a character.
## Set power, damage_type, crit_chance etc. directly on the token in the inspector.
@export var token: RuntimeToken
```

- [ ] **Step 2: Create Skill_Effect_Grant.gd**

```gdscript
class_name Skill_Effect_Grant
extends Skill_Effect_Base

## Token blueprint to attach to the target. Creates `amount` separate instances.
## Each instance fires once when its trigger condition is met, then is removed.
@export var token: RuntimeToken
@export var amount: int = 1
```

- [ ] **Step 3: Create Skill_Effect_Remove.gd**

```gdscript
class_name Skill_Effect_Remove
extends Skill_Effect_Base

## Remove all tokens of a given type from the target (cleanse, dispel, purge).
## Set amount to -1 to remove all instances; set to N to remove exactly N.
@export var token_type: String = ""
@export var amount: int = -1
```

- [ ] **Step 4: Clean up Skill_Effect_Base**

Replace the entire file:

```gdscript
class_name Skill_Effect_Base
extends Resource

## ChanceTier is used by RuntimeToken_Damage and CombatCalculator.hit_roll.
## Physical attacks: scales HIT stat in hit formula.
## Ailments (future): raw application probability before resistance.
## Magical damage, heals, buffs: ignored — these always connect.
enum ChanceTier {
	CERTAIN,  # 100% tier
	HIGH,     # 75% tier
	MEDIUM,   # 50% tier
	LOW,      # 25% tier
}

@export var needs_previous_hit: bool = false
```

- [ ] **Step 5: Validate in Godot**

Check for script errors. `CombatCalculator` still compiles because `Skill_Effect_Base.ChanceTier` still exists. `RuntimeToken_Damage` still compiles for the same reason. No crashes expected.

- [ ] **Step 6: Commit**

```bash
git add scripts/combat/skills/effects/Skill_Effect_Instant.gd scripts/combat/skills/effects/Skill_Effect_Grant.gd scripts/combat/skills/effects/Skill_Effect_Remove.gd scripts/combat/skills/effects/Skill_Effect_Base.gd
git commit -m "feat: add Skill_Effect_Instant/Grant/Remove — universal effect classes; clean up Skill_Effect_Base"
```

---

## Task 5: Rewrite SkillExecutor as 3-path factory

Drop the old token factories. The executor no longer knows about damage types, DoT tags, or any token internals — it just routes to the right path and lets the token do its job.

**Files:**
- Modify: `scripts/combat/SkillExecutor.gd`

- [ ] **Step 1: Replace SkillExecutor entirely**

```gdscript
class_name SkillExecutor

static func execute(context: ActionContext) -> void:
	for effect in context.mnemonic.effect_steps:
		if effect.needs_previous_hit and not context.any_hit:
			context.record_step(false, 0, false)
			continue

		if effect is Skill_Effect_Instant:
			_fire_instant(effect, context)
		elif effect is Skill_Effect_Grant:
			_grant_tokens(effect, context)
		elif effect is Skill_Effect_Remove:
			_remove_tokens(effect, context)
		else:
			Log.warn("SkillExecutor — unknown effect type", effect.get_class())

static func _fire_instant(effect: Skill_Effect_Instant, context: ActionContext) -> void:
	if effect.token == null:
		Log.error("SkillExecutor — Skill_Effect_Instant has no token", context.mnemonic.mnemonic_name)
		return
	var token := effect.token.duplicate(true) as RuntimeToken
	token.source = context.source
	token.owner = context.target
	token.fire(context)

static func _grant_tokens(effect: Skill_Effect_Grant, context: ActionContext) -> void:
	if effect.token == null:
		Log.error("SkillExecutor — Skill_Effect_Grant has no token", context.mnemonic.mnemonic_name)
		return
	for i in range(effect.amount):
		var token := effect.token.duplicate(true) as RuntimeToken
		token.source = context.source
		token.owner = context.target
		context.target.tokens.add_token(token)
		context.tokens_applied.append(token)

static func _remove_tokens(effect: Skill_Effect_Remove, context: ActionContext) -> void:
	# TODO: implement when cleanse mnemonics are authored
	Log.warn("SkillExecutor — Skill_Effect_Remove not yet wired", effect.token_type)
```

- [ ] **Step 2: Validate in Godot — expect broken mnemonics**

The game will load but active mnemonics (`viper_strike.tres`, `uskrav_tergo_lupi.tres`, `enemy_basic_strike.tres`) still use `Skill_Effect_Damage` and `Skill_Effect_DoT`. SkillExecutor will log "unknown effect type" warnings but won't crash. Verify: open the Godot editor, check for script errors (there should be none), run the scene briefly to confirm no crash.

> Do NOT commit yet — wait for Task 6 (mnemonic migration) to restore working combat.

---

## Task 6: Migrate all mnemonics

Update all `.tres` mnemonic files to use `Skill_Effect_Instant` and `Skill_Effect_Grant`. Do this in the Godot editor — the inspector handles resource types correctly and won't corrupt UIDs.

**Files:**
- Modify: `resources/mnemonics/enemy_basic_strike.tres`
- Modify: `resources/mnemonics/uskrav_tergo_lupi.tres`
- Modify: `resources/mnemonics/viper_strike.tres`
- Modify: `resources/mnemonics/effect_blunt_15.tres`
- Modify: `resources/mnemonics/effect_slash_30.tres`

### For each damage-only mnemonic (enemy_basic_strike, uskrav_tergo_lupi, effect_blunt_15, effect_slash_30):

- [ ] **Step 1: Open mnemonic in Godot inspector**

In FileSystem dock, double-click the `.tres` file to open it in the inspector.

- [ ] **Step 2: Replace the effect step**

In `effect_steps`, delete the existing `Skill_Effect_Damage` entry. Add a new element, set its type to `Skill_Effect_Instant`.

Inside the `Skill_Effect_Instant`, set `token` to a new inline resource of type `RuntimeToken_Damage`. Configure:
- `power` — match the old value (enemy_basic_strike: 15, uskrav_tergo_lupi: 30, effect_blunt_15: 15, effect_slash_30: 30)
- `damage_type` — match the old value (enemy_basic_strike: Blunt=2, uskrav_tergo_lupi: Slash=0)
- `inherit_from_weapon` — match old value (enemy_basic_strike: false, uskrav_tergo_lupi: true)
- `crit_chance` — match old value (enemy_basic_strike: 3, uskrav_tergo_lupi: 5 default)

- [ ] **Step 3: Save**

Ctrl+S. Godot writes the updated `.tres`.

### For viper_strike.tres:

- [ ] **Step 4: Open viper_strike.tres in inspector**

- [ ] **Step 5: Replace first effect step (damage)**

Replace `Skill_Effect_Damage` with `Skill_Effect_Instant`. Set `token` to inline `RuntimeToken_Damage`:
- `power = 25`
- `damage_type = Pierce (1)`
- `inherit_from_weapon = false`
- `needs_previous_hit = false`

- [ ] **Step 6: Replace second effect step (DoT → Grant)**

Replace `Skill_Effect_DoT` with `Skill_Effect_Grant`. Configure:
- `needs_previous_hit = true`
- `amount = 2`
- `token` = inline `RuntimeToken_Poison` (no fields to set — behavior is fixed)

- [ ] **Step 7: Save**

Ctrl+S.

- [ ] **Step 8: Verify in Godot — run combat**

Run the main scene. Start combat. Have Skugge use Viper Strike:
- Enemy should take pierce damage
- Enemy should have `POISON×2` in its token display
- On the enemy's next turn start, one POISON fires → enemy takes `max_hp×10% + max_mp×10%` damage, display drops to `POISON×1`
- On the following turn, second POISON fires, display disappears

Check Godot output log for confirmation. No crashes.

- [ ] **Step 9: Commit**

```bash
git add resources/mnemonics/
git commit -m "feat: migrate all mnemonics to Skill_Effect_Instant/Grant — token system v2 fully wired"
```

---

## Task 7: Update ActionPipeline — remove tokens after firing

Reaction tokens (PRE and POST queue) are single-use. The pipeline must remove them from the owner's `ActiveTokens` after they fire.

**Files:**
- Modify: `scripts/combat/ActionPipeline.gd`

- [ ] **Step 1: Add remove_token call in PRE pass**

Find the PRE pass loop (around line 32):

```gdscript
for token in context.pre_queue:
    var reaction_ctx := ActionContext.new()
    reaction_ctx.trigger_context = context
    token.fire(reaction_ctx)
    if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
        Log.info("ActionPipeline — downed (pre-reaction)", reaction_ctx.target.character_name)
        CombatEvents.actor_downed.emit(reaction_ctx.target)
```

Add `token.owner.tokens.remove_token(token)` after `token.fire(reaction_ctx)`:

```gdscript
for token in context.pre_queue:
    var reaction_ctx := ActionContext.new()
    reaction_ctx.trigger_context = context
    token.fire(reaction_ctx)
    token.owner.tokens.remove_token(token)
    if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
        Log.info("ActionPipeline — downed (pre-reaction)", reaction_ctx.target.character_name)
        CombatEvents.actor_downed.emit(reaction_ctx.target)
```

- [ ] **Step 2: Add remove_token call in POST pass**

Same change in the POST pass loop (around line 71):

```gdscript
for token in context.post_queue:
    var reaction_ctx := ActionContext.new()
    reaction_ctx.trigger_context = context
    token.fire(reaction_ctx)
    token.owner.tokens.remove_token(token)
    if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
        Log.info("ActionPipeline — downed (post-reaction)", reaction_ctx.target.character_name)
        CombatEvents.actor_downed.emit(reaction_ctx.target)
```

- [ ] **Step 3: Validate in Godot**

Run combat. No crash expected. Reaction tokens (when implemented) will be correctly removed after firing.

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/ActionPipeline.gd
git commit -m "fix: remove reaction tokens from ActiveTokens after firing in pre/post pass"
```

---

## Task 8: Author DoT token blueprints

Create the shared `.tres` blueprints for Poison, Burn, and Bleed. These are referenced by `Skill_Effect_Grant` in any mnemonic that applies DoT effects.

**Files:**
- Create: `resources/tokens/poison_base.tres`
- Create: `resources/tokens/burn_base.tres`
- Create: `resources/tokens/bleed_base.tres`

- [ ] **Step 1: Create resources/tokens/ folder**

In the Godot FileSystem dock, right-click `resources/` → New Folder → `tokens`.

- [ ] **Step 2: Create poison_base.tres**

In FileSystem dock, right-click `resources/tokens/` → New Resource → select `RuntimeToken_Poison` → save as `poison_base.tres`.

No fields to configure — `RuntimeToken_Poison` has no exported fields. The behavior is entirely in `tick()`.

- [ ] **Step 3: Create burn_base.tres**

Same as above but `RuntimeToken_Burn` → save as `burn_base.tres`.

- [ ] **Step 4: Create bleed_base.tres**

Same — `RuntimeToken_Bleed` → `bleed_base.tres`.

- [ ] **Step 5: Update viper_strike.tres to reference poison_base.tres**

Open `viper_strike.tres` in the inspector. In the `Skill_Effect_Grant` step, change the `token` field from the inline `RuntimeToken_Poison` to the shared `poison_base.tres` blueprint (drag from FileSystem or use the resource picker).

This is optional but recommended — using the shared blueprint means all future POISON grants reference the same definition.

- [ ] **Step 6: Commit**

```bash
git add resources/tokens/
git commit -m "feat: author poison_base, burn_base, bleed_base token blueprints"
```

---

## Task 9: Delete dead files

**Files:**
- Delete: `scripts/combat/tokens/RuntimeToken_DoT.gd`
- Delete: `scripts/combat/skills/effects/Skill_Effect_Damage.gd`
- Delete: `scripts/combat/skills/effects/Skill_Effect_DoT.gd`

- [ ] **Step 1: Confirm nothing references the old files**

```bash
grep -rn "RuntimeToken_DoT\|Skill_Effect_Damage\|Skill_Effect_DoT" /home/bart/Projects/neverworld-v-2/scripts --include="*.gd"
grep -rn "RuntimeToken_DoT\|Skill_Effect_Damage\|Skill_Effect_DoT" /home/bart/Projects/neverworld-v-2/resources --include="*.tres"
```

Expected output: empty. If anything still references them, fix it before deleting.

- [ ] **Step 2: Delete the files**

```bash
rm /home/bart/Projects/neverworld-v-2/scripts/combat/tokens/RuntimeToken_DoT.gd
rm /home/bart/Projects/neverworld-v-2/scripts/combat/skills/effects/Skill_Effect_Damage.gd
rm /home/bart/Projects/neverworld-v-2/scripts/combat/skills/effects/Skill_Effect_DoT.gd
```

- [ ] **Step 3: Rescan filesystem in Godot**

In Godot editor: Project → Reload Current Project (or press F5 to re-open). Confirm no missing-script errors in the FileSystem dock.

- [ ] **Step 4: Final verification — run full combat**

Run the main scene. Complete a full combat encounter:
- Basic attack (Uskrav) → deals damage ✓
- Viper Strike → deals damage + applies POISON×2 ✓
- Enemy turn start → POISON fires once, POISON×1 remains ✓
- Enemy turn start again → POISON fires, disappears ✓
- Check Godot output for any warnings about unknown effect types ✓

- [ ] **Step 5: Final commit**

```bash
git add -u
git commit -m "refactor: delete RuntimeToken_DoT, Skill_Effect_Damage, Skill_Effect_DoT — token system v2 complete"
```

---

## Self-Review Checklist

- [x] RuntimeToken extends Resource → blueprints authorable as .tres
- [x] No charges field on token — duration from quantity, not counter
- [x] ActiveTokens.add_token: no charge stacking, plain append
- [x] ActiveTokens.tick_turn_start: fires ONE per type, removes it
- [x] ActiveTokens.collect_triggers: returns ONE per type
- [x] ActiveTokens.remove_token: new method for pipeline to call after reactions fire
- [x] SkillExecutor: 3 paths, no token construction knowledge
- [x] ActionPipeline: removes tokens from owner after they fire
- [x] DoT subclasses: Poison/Burn/Bleed each have their own formula
- [x] Skill_Effect_Base: keeps ChanceTier enum, drops exported fields
- [x] All 5 existing mnemonics migrated
- [x] Dead files deleted
- [x] Viper Strike end-to-end verified
