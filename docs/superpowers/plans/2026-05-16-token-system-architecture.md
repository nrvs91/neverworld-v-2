# Token System Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the combat effect pipeline so every effect is a self-resolving token, implement DoT ticking on TurnStart, author Viper Strike (Pierce + POISON) as end-to-end validation.

**Architecture:** `SkillExecutor` becomes a factory that creates `RuntimeToken` instances from effect blueprints and fires or stores them. `ActionContext` is created in `CombatFSM` before `SkillExecutor` runs and serves as the shared resolution scratchpad. Instant tokens (`RuntimeToken_Damage`) fire and expire during resolution. Persistent tokens (`RuntimeToken_DoT`) attach to the target's `ActiveTokens` and tick on `TurnStart`.

**Tech Stack:** GDScript, Godot 4.6, no automated tests — verification is manual via combat scene run and Godot Output panel.

---

## File Map

**Create:**
- `scripts/combat/tokens/RuntimeToken.gd` — base class: trigger enum, charges, source, owner, fire()/tick() stubs
- `scripts/combat/tokens/RuntimeToken_Damage.gd` — INSTANT token, moves _resolve_damage logic from SkillExecutor
- `scripts/combat/tokens/RuntimeToken_DoT.gd` — ON_TURN_START token, tick() formula per dot_tag
- `scripts/combat/skills/effects/Skill_Effect_DoT.gd` — authored resource: dot_tag + charges

**Modify:**
- `scripts/combat/VitalsComponent.gd` — make `max_mp` public (was `_max_mp`)
- `scripts/combat/CombatEvents.gd` — add `dot_ticked` signal
- `scripts/combat/ActionContext.gd` — add `tokens_applied`, add `record_step()`, remove `ailments_applied`
- `scripts/combat/ActiveTokens.gd` — full implementation: _tokens storage, add_token(), tick_turn_start(), get_display_text(), flush()
- `scripts/combat/SkillExecutor.gd` — rewrite as factory; new signature `execute(context)`
- `scripts/combat/CombatFSM.gd` — create ActionContext in FSM, remove damage loop (tokens handle it)
- `scripts/combat/ui/PlayerCard.gd` — connect to tokens signals, refresh token label
- `scenes/combat/ui/player_card.tscn` — add Label inside existing TokenContainer
- `scripts/combat/ui/EnemyCard.gd` — connect to tokens signals, refresh token label
- `scenes/combat/ui/enemy_card.tscn` — add Label inside existing TokenContainer

---

## Task 1: Make `max_mp` public in VitalsComponent

**Files:**
- Modify: `scripts/combat/VitalsComponent.gd`

`RuntimeToken_DoT` needs `owner.vitals.max_mp` for the POISON formula. Currently `_max_mp` is private.

- [ ] **Step 1: Open `scripts/combat/VitalsComponent.gd` and change the private field to public**

Change line 14 from:
```gdscript
var _max_mp: int = 0
```
To:
```gdscript
var max_mp: int = 0
```

Then update the two internal references. In `setup()`, change:
```gdscript
_max_mp = max_mp
cur_mp = max_mp
```
To:
```gdscript
max_mp = max_mp_val
cur_mp = max_mp_val
```

And update the `setup()` parameter name to avoid shadowing. Final `setup()`:
```gdscript
func setup(max_hp_val: int, max_mp_val: int) -> void:
	max_hp = max_hp_val
	max_mp = max_mp_val
	cur_hp = max_hp_val
	cur_mp = max_mp_val
	cur_ap = 3
	cur_ct = 0.0
	Log.debug("VitalsComponent setup")
```

- [ ] **Step 2: Verify Godot parses cleanly**

Open Godot. Check Output panel — no errors. Run the combat scene briefly to confirm it still starts without crashing.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/VitalsComponent.gd
git commit -m "fix: make max_mp public on VitalsComponent — needed by DoT tick formula"
```

---

## Task 2: Add `dot_ticked` signal to CombatEvents

**Files:**
- Modify: `scripts/combat/CombatEvents.gd`

`RuntimeToken_DoT.tick()` emits this signal so the damage number system can show DoT damage.

- [ ] **Step 1: Add the signal**

In `scripts/combat/CombatEvents.gd`, add after the existing signals:
```gdscript
signal dot_ticked(token: RuntimeToken, context: ActionContext)
```

Carries the token (metadata: owner, dot_tag, damage_type) and the context (results: total_damage, any_hit). Consumers get everything without bespoke parameters. Future reactive tokens like BLOOD SCENT listen here and read what they need.

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/CombatEvents.gd
git commit -m "feat: dot_ticked signal carries (token, context) — full resolution facts for reactive tokens"
```

---

## Task 3: Create `Skill_Effect_DoT` resource

**Files:**
- Create: `scripts/combat/skills/effects/Skill_Effect_DoT.gd`

The authored data resource for DoT effects. Lives alongside `Skill_Effect_Damage.gd`.

- [ ] **Step 1: Create the file**

```gdscript
class_name Skill_Effect_DoT
extends Skill_Effect_Base

enum DotTag { POISON, BURN, BLEED }

@export var dot_tag: DotTag = DotTag.POISON
@export var charges: int = 3
```

`charges` is how many turns the DoT lasts. Damage formula is fixed per `dot_tag` — not authored per instance (see GDD). `needs_previous_hit` is inherited from `Skill_Effect_Base` — set `true` on Viper Strike's POISON step so it only applies if the Pierce hit landed.

- [ ] **Step 2: Verify in Godot**

In the Godot FileSystem dock, right-click `scripts/combat/skills/effects/` → New Resource → search for `Skill_Effect_DoT`. Confirm `dot_tag` dropdown shows POISON/BURN/BLEED and `charges` appears. Close without saving.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/skills/effects/Skill_Effect_DoT.gd
git commit -m "feat: Skill_Effect_DoT resource — dot_tag, charges, inherits needs_previous_hit"
```

---

## Task 4: Create `RuntimeToken` base class

**Files:**
- Create: `scripts/combat/tokens/RuntimeToken.gd`

The base for every runtime token. Defines the trigger enum and the two resolution methods subclasses implement.

- [ ] **Step 1: Create the `scripts/combat/tokens/` folder and the file**

```gdscript
class_name RuntimeToken
extends RefCounted

enum Trigger {
	INSTANT,
	ON_TURN_START,
	ON_DAMAGE_TAKEN,  # stub — not dispatched yet (COUNTER, BRACE)
	ON_ALLY_HIT,      # stub — not dispatched yet (VIGIL, FOLLOW UP)
	PRE_EXECUTION,    # stub — not dispatched yet (PREMONITION, COVER)
}

var token_type: String = ""
var trigger: Trigger = Trigger.INSTANT
var charges: int = 1
var source: CombatCharacter = null
var owner: CombatCharacter = null

## Called by SkillExecutor for INSTANT tokens during mnemonic resolution.
## Reads context.any_hit for conditional chaining. Writes result via context.record_step().
func fire(_context: ActionContext) -> void:
	pass

## Called by ActiveTokens.tick_turn_start() for ON_TURN_START tokens.
## ActiveTokens creates one fresh context per token before calling this.
## mnemonic/attacker/primary_target are null on that context — read self.owner/self.source instead.
func tick(_context: ActionContext) -> void:
	pass
```

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken.gd
git commit -m "feat: RuntimeToken base class — Trigger enum, fire(), tick() stubs"
```

---

## Task 5: Update `ActionContext`

**Files:**
- Modify: `scripts/combat/ActionContext.gd`

Add `tokens_applied`, add `record_step()`, remove the now-unused `ailments_applied`. ActionContext is now created in CombatFSM (not inside SkillExecutor), so attacker/target are set there before passing to SkillExecutor.

- [ ] **Step 1: Rewrite the file**

```gdscript
class_name ActionContext
extends RefCounted

var mnemonic: MnemonicResource
var attacker: CombatCharacter
var primary_target: CombatCharacter

var step_results: Array = []
var tokens_applied: Array = []
var total_damage: int = 0
var any_hit: bool = false
var any_crit: bool = false

## Called by INSTANT tokens (RuntimeToken_Damage) after resolving.
## any_hit is ONLY set here — persistent token attachment never touches it.
func record_step(hit: bool, damage: int, is_crit: bool) -> void:
	step_results.append({hit = hit, damage = damage, is_crit = is_crit})
	if hit:
		any_hit = true
		total_damage += damage
	if is_crit:
		any_crit = true
```

Note: `MnemonicResource` is a `class_name` type. If Godot reports "could not find type MnemonicResource" on parse, add a preload at the top:
```gdscript
const MnemonicResource = preload("res://scripts/combat/skills/MnemonicResource.gd")
```

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ActionContext.gd
git commit -m "feat: ActionContext — record_step(), tokens_applied, any_hit contract enforced"
```

---

## Task 6: Create `RuntimeToken_Damage`

**Files:**
- Create: `scripts/combat/tokens/RuntimeToken_Damage.gd`

INSTANT token. Moves the existing `SkillExecutor._resolve_damage()` logic here. Handles its own hit/miss/crit/resistance pipeline, applies damage to `owner.vitals`, emits `action_executed` or `MISS` text, then writes to context via `record_step()`.

- [ ] **Step 1: Create the file**

```gdscript
class_name RuntimeToken_Damage
extends RuntimeToken

var power: int = 10
var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Slash
var crit_chance: int = 5
var chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH
var inherit_from_weapon: bool = true
var true_strike: bool = false

func _init() -> void:
	token_type = "DAMAGE"
	trigger = Trigger.INSTANT

func fire(context: ActionContext) -> void:
	var is_phys: bool = _is_physical(damage_type)

	var is_crit: bool = CombatCalculator.crit_roll(crit_chance)

	if is_phys and not is_crit and not true_strike:
		var hit_stat: int = source.stats.stat(CharacterStats.Stat.Hit)
		var dodge_stat: int = owner.stats.stat(CharacterStats.Stat.Dodge)
		if not CombatCalculator.hit_roll(hit_stat, dodge_stat, chance_tier):
			Log.info("RuntimeToken_Damage — missed", "%s->%s" % [source.character_name, owner.character_name])
			CombatEvents.combat_text_shown.emit(owner, "MISS")
			context.record_step(false, 0, false)
			return

	var effective_type: ResistanceType.DamageType = damage_type
	if is_phys and inherit_from_weapon:
		effective_type = _get_weapon_damage_type()

	var atk_stat := CharacterStats.Stat.AtkPhys if is_phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if is_phys else CharacterStats.Stat.DefMag
	var atk: int = source.stats.stat(atk_stat)
	var def_val: int = owner.stats.stat(def_stat)
	var raw: int = CombatCalculator.calc_damage(power, atk, def_val)

	if is_crit:
		raw *= 2

	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(effective_type)
	var final_damage: int = max(0, int(raw * CombatCalculator.resist_multiplier(resist_state)))

	var summary := "%s->%s %d (crit:%s resist:%s)" % [source.character_name, owner.character_name,
		final_damage, is_crit, ResistanceType.State.keys()[resist_state]]
	Log.info("RuntimeToken_Damage", summary)

	# Apply damage BEFORE emitting — listeners read post-damage vitals
	owner.vitals.take_damage(final_damage)
	CombatEvents.action_executed.emit(source, owner, final_damage)
	context.record_step(true, final_damage, is_crit)

static func _is_physical(dt: ResistanceType.DamageType) -> bool:
	return dt == ResistanceType.DamageType.Slash \
		or dt == ResistanceType.DamageType.Pierce \
		or dt == ResistanceType.DamageType.Blunt

static func _get_weapon_damage_type() -> ResistanceType.DamageType:
	# TODO: read from attacker's equipped weapon once gear system exists.
	return ResistanceType.DamageType.Slash
```

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_Damage.gd
git commit -m "feat: RuntimeToken_Damage — INSTANT token, hit/crit/resist pipeline, self-applies damage"
```

---

## Task 7: Create `RuntimeToken_DoT`

**Files:**
- Create: `scripts/combat/tokens/RuntimeToken_DoT.gd`

ON_TURN_START token. `tick()` calculates damage from the owner's max HP/MP using the GDD-fixed formula per dot_tag, applies resistance, calls `owner.vitals.take_damage()`, and emits `dot_ticked`.

- [ ] **Step 1: Create the file**

```gdscript
class_name RuntimeToken_DoT
extends RuntimeToken

var dot_tag: String = "POISON"
var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Nature

func _init() -> void:
	trigger = Trigger.ON_TURN_START

## GDD tick formulas (fixed per dot_tag, not authored per instance):
##   POISON — (max_hp × 10% + max_mp × 10%) × resist_mult
##   BURN   — max_hp × 10% × resist_mult
##   BLEED  — max_hp × 10% × resist_mult
## Context is created fresh per-token by ActiveTokens. mnemonic/attacker/primary_target are null.
func tick(context: ActionContext) -> void:
	var resist_state := ResistanceType.State.NONE
	if owner.resistance_profile != null:
		resist_state = owner.resistance_profile.get_state(damage_type)
	var resist_mult: float = CombatCalculator.resist_multiplier(resist_state)

	# IMMUNE (resist_mult == 0) — no damage, no broadcast, charges still decrement
	if resist_mult == 0.0:
		Log.info("RuntimeToken_DoT — IMMUNE, tick skipped", owner.character_name)
		return

	var raw: float
	match dot_tag:
		"POISON":
			raw = (owner.vitals.max_hp * 0.1 + owner.vitals.max_mp * 0.1) * resist_mult
		"BURN":
			raw = owner.vitals.max_hp * 0.1 * resist_mult
		"BLEED":
			raw = owner.vitals.max_hp * 0.1 * resist_mult
		_:
			Log.warn("RuntimeToken_DoT — unknown dot_tag", dot_tag)
			return

	var damage: int = max(1, int(raw))
	Log.info("RuntimeToken_DoT tick", "%s %s %d dmg" % [owner.character_name, dot_tag, damage])
	owner.vitals.take_damage(damage)
	context.record_step(true, damage, false)
	CombatEvents.dot_ticked.emit(self, context)
```

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken_DoT.gd
git commit -m "feat: RuntimeToken_DoT — ON_TURN_START, GDD tick formulas for POISON/BURN/BLEED"
```

---

## Task 8: Implement `ActiveTokens`

**Files:**
- Modify: `scripts/combat/ActiveTokens.gd`

Replace the stub with full storage, ticking, expiry, and display text. The three signals (`token_added`, `token_removed`, `token_updated`) are already declared in the stub.

- [ ] **Step 1: Rewrite the file**

```gdscript
class_name ActiveTokens
extends Node

signal token_added(token: RuntimeToken)
signal token_removed(token: RuntimeToken)
signal token_updated(token: RuntimeToken)

var _tokens: Array[RuntimeToken] = []

func add_token(token: RuntimeToken) -> void:
	_tokens.append(token)
	Log.info("ActiveTokens — added", "%s %s" % [token.owner.character_name, token.token_type])
	token_added.emit(token)

## Fire all ON_TURN_START tokens, decrement charges, remove expired ones.
## One fresh ActionContext per token — no cross-contamination between ticks.
## Called by CombatFSM at the start of the active actor's turn.
func tick_turn_start() -> void:
	var to_remove: Array[RuntimeToken] = []
	for token in _tokens:
		if token.trigger != RuntimeToken.Trigger.ON_TURN_START:
			continue
		var ctx := ActionContext.new()
		token.tick(ctx)
		token.charges -= 1
		if token.charges <= 0:
			to_remove.append(token)
	for token in to_remove:
		_tokens.erase(token)
		Log.info("ActiveTokens — expired", "%s %s" % [token.owner.character_name, token.token_type])
		token_removed.emit(token)

## Returns a display string for the card UI. Format: "POISON×3 BURN×2"
func get_display_text() -> String:
	if _tokens.is_empty():
		return ""
	var parts: Array = []
	for token in _tokens:
		parts.append("%s×%d" % [token.token_type, token.charges])
	return " ".join(parts)

func flush() -> void:
	_tokens.clear()
	Log.info("ActiveTokens flushed")
```

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ActiveTokens.gd
git commit -m "feat: ActiveTokens — storage, tick_turn_start(), expiry, get_display_text()"
```

---

## Task 9: Rewrite `SkillExecutor` as factory

**Files:**
- Modify: `scripts/combat/SkillExecutor.gd`

New signature: `execute(context)` — receives the already-created ActionContext from CombatFSM. Creates tokens from effect blueprints, fires INSTANT tokens immediately, attaches persistent tokens to target's `ActiveTokens`.

- [ ] **Step 1: Rewrite the file**

```gdscript
class_name SkillExecutor
## Token factory. Creates RuntimeToken instances from a mnemonic's effect steps.
## Receives an ActionContext created by CombatFSM — does not create its own.

const SkillEffectDamage = preload("res://scripts/combat/skills/effects/Skill_Effect_Damage.gd")
const SkillEffectDoT = preload("res://scripts/combat/skills/effects/Skill_Effect_DoT.gd")

static func execute(context: ActionContext) -> void:
	for effect in context.mnemonic.effect_steps:
		if effect.needs_previous_hit and not context.any_hit:
			context.record_step(false, 0, false)
			continue

		var token: RuntimeToken = _create_token(effect, context.attacker, context.primary_target)

		if token.trigger == RuntimeToken.Trigger.INSTANT:
			token.fire(context)
		else:
			context.primary_target.tokens.add_token(token)
			context.tokens_applied.append(token)

static func _create_token(effect: Skill_Effect_Base, attacker: CombatCharacter, target: CombatCharacter) -> RuntimeToken:
	if effect is SkillEffectDamage:
		return _create_damage_token(effect as SkillEffectDamage, attacker, target)
	if effect is SkillEffectDoT:
		return _create_dot_token(effect as SkillEffectDoT, attacker, target)
	Log.warn("SkillExecutor — unknown effect type", effect.get_class())
	var fallback := RuntimeToken.new()
	fallback.source = attacker
	fallback.owner = target
	return fallback

static func _create_damage_token(effect: SkillEffectDamage, attacker: CombatCharacter, target: CombatCharacter) -> RuntimeToken_Damage:
	var token := RuntimeToken_Damage.new()
	token.source = attacker
	token.owner = target
	token.power = effect.power
	token.damage_type = effect.damage_type
	token.crit_chance = effect.crit_chance
	token.chance_tier = effect.chance_tier
	token.inherit_from_weapon = effect.inherit_from_weapon
	token.true_strike = effect.true_strike
	return token

static func _create_dot_token(effect: SkillEffectDoT, attacker: CombatCharacter, target: CombatCharacter) -> RuntimeToken_DoT:
	var token := RuntimeToken_DoT.new()
	token.source = attacker
	token.owner = target
	token.charges = effect.charges
	match effect.dot_tag:
		Skill_Effect_DoT.DotTag.POISON:
			token.dot_tag = "POISON"
			token.token_type = "POISON"
			token.damage_type = ResistanceType.DamageType.Nature
		Skill_Effect_DoT.DotTag.BURN:
			token.dot_tag = "BURN"
			token.token_type = "BURN"
			token.damage_type = ResistanceType.DamageType.Fire
		Skill_Effect_DoT.DotTag.BLEED:
			token.dot_tag = "BLEED"
			token.token_type = "BLEED"
			token.damage_type = ResistanceType.DamageType.Bleed
	return token
```

- [ ] **Step 2: Verify parse**

Open Godot. Check Output — no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/SkillExecutor.gd
git commit -m "feat: SkillExecutor rewritten as token factory — execute(context), creates RuntimeToken instances"
```

---

## Task 10: Update `CombatFSM` — ACTION_EXECUTION

**Files:**
- Modify: `scripts/combat/CombatFSM.gd`

Two changes: ActionContext is now created in the FSM before calling SkillExecutor. The damage application loop is removed — `RuntimeToken_Damage.fire()` handles damage and event emission directly. `tick_turn_start()` is already called on line 50 — no change needed there.

- [ ] **Step 1: Replace `_enter_action_execution()`**

Replace the entire function:

```gdscript
func _enter_action_execution() -> void:
	if _pending_mnemonic == null:
		Log.warn("ActionExecution — no mnemonic, skipping to REACTION_SCAN")
		_transition(State.REACTION_SCAN)
		return

	if _active_actor.vitals.cur_ap < _pending_mnemonic.ap_cost \
			or _active_actor.vitals.cur_mp < _pending_mnemonic.mp_cost:
		Log.warn("ActionExecution — insufficient AP/MP, skipping skill")
		_transition(State.REACTION_SCAN)
		return

	_active_actor.vitals.spend_ap(_pending_mnemonic.ap_cost)
	_active_actor.vitals.spend_mp(_pending_mnemonic.mp_cost)

	# ActionContext is created here so future PRE_EXECUTION reactions can write to it
	# before SkillExecutor runs (e.g. COVER redirects primary_target, PREMONITION negates)
	var context := ActionContext.new()
	context.mnemonic = _pending_mnemonic
	context.attacker = _active_actor
	context.primary_target = _pending_target

	SkillExecutor.execute(context)

	if _pending_mnemonic.hp_cost_percent > 0.0:
		_active_actor.vitals.spend_hp_percent(_pending_mnemonic.hp_cost_percent)

	# Tokens handled damage application and action_executed emission.
	# FSM reads final context state for bookkeeping only.
	Log.info("ActionExecution", "%s->%s total:%d" % [
		_active_actor.character_name, context.primary_target.character_name, context.total_damage])

	if context.primary_target.vitals.is_downed():
		Log.info("actor downed", context.primary_target.character_name)
		CombatEvents.actor_downed.emit(context.primary_target)

	CombatEvents.action_resolved.emit(_active_actor)

	if _check_combat_end():
		return
	_transition(State.REACTION_SCAN)
```

- [ ] **Step 2: Run the combat scene — full smoke test**

Run the combat scene (F5). Walk through a full combat:

1. Enemy turn fires automatically — check Output for `RuntimeToken_Damage` log lines, confirm damage number appears
2. Player turn — navigate to ACT, select a skill, confirm target — check Output for hit/miss/damage
3. Confirm no errors in Output panel
4. Confirm existing mnemonics (Skugge's Tergo Lupi, enemy Strike) still work correctly

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/CombatFSM.gd
git commit -m "feat: CombatFSM ACTION_EXECUTION — ActionContext created in FSM, token factory pipeline"
```

---

## Task 11: Token display on PlayerCard and EnemyCard

**Files:**
- Modify: `scripts/combat/ui/PlayerCard.gd`
- Modify: `scenes/combat/ui/player_card.tscn`
- Modify: `scripts/combat/ui/EnemyCard.gd`
- Modify: `scenes/combat/ui/enemy_card.tscn`

Both `.tscn` files already have a `TokenContainer` (HBoxContainer) node. Add a Label child inside it and wire the card scripts to `tokens.token_added` / `tokens.token_removed` signals.

- [ ] **Step 1: Add TokenLabel to `player_card.tscn`**

Use the Godot MCP tool to add a Label node inside the existing `TokenContainer`:

```
mcp__godot__add_node:
  scene_path: "res://scenes/combat/ui/player_card.tscn"
  node_type: "Label"
  node_name: "TokenLabel"
  parent_path: "VBox/TokenContainer"
```

Then set properties:
```
mcp__godot__set_node_properties:
  scene_path: "res://scenes/combat/ui/player_card.tscn"
  node_path: "VBox/TokenContainer/TokenLabel"
  properties: {
    "layout_mode": 2,
    "theme_override_font_sizes/font_size": 5,
    "text": ""
  }
```

- [ ] **Step 2: Add TokenLabel to `enemy_card.tscn`**

```
mcp__godot__add_node:
  scene_path: "res://scenes/combat/ui/enemy_card.tscn"
  node_type: "Label"
  node_name: "TokenLabel"
  parent_path: "VBox/TokenContainer"
```

Then set properties:
```
mcp__godot__set_node_properties:
  scene_path: "res://scenes/combat/ui/enemy_card.tscn"
  node_path: "VBox/TokenContainer/TokenLabel"
  properties: {
    "layout_mode": 2,
    "theme_override_font_sizes/font_size": 5,
    "text": ""
  }
```

- [ ] **Step 3: Update `PlayerCard.gd`**

Add `@onready` for the label and wire token signals in `setup()`:

```gdscript
class_name PlayerCard
extends Control

const NUDGE_AMOUNT: float = 12.0
const NUDGE_DURATION: float = 0.12

@onready var hp_bar: TextureProgressBar = $VBox/TopBar/HPBar
@onready var mp_bar: TextureProgressBar = $VBox/TopBar/MPBar
@onready var ap_bar: TextureProgressBar = $VBox/APBar
@onready var hp_value: Label = $VBox/TopBar/HPBar/HP/HPValue
@onready var mp_value: Label = $VBox/TopBar/MPBar/MP/MPValue
@onready var ap_value: Label = $VBox/APBar/AP/APValue
@onready var portrait_rect: TextureRect = $VBox/Portrait/Portrait
@onready var _token_label: Label = $VBox/TokenContainer/TokenLabel

var _actor: CombatCharacter = null

func setup(actor: CombatCharacter) -> void:
	_actor = actor
	hp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxHP)
	mp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxMP)
	ap_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxAP)
	actor.vitals.vitals_changed.connect(refresh_vitals)
	actor.tokens.token_added.connect(_refresh_token_display)
	actor.tokens.token_removed.connect(_refresh_token_display)
	# portrait_rect.texture = actor.portrait_texture
	refresh_vitals()

func refresh_vitals() -> void:
	if _actor == null:
		return
	hp_bar.value = _actor.vitals.cur_hp
	mp_bar.value = _actor.vitals.cur_mp
	ap_bar.value = _actor.vitals.cur_ap
	hp_value.text = str(_actor.vitals.cur_hp)
	mp_value.text = str(_actor.vitals.cur_mp)
	ap_value.text = str(_actor.vitals.cur_ap)

func _refresh_token_display(_token = null) -> void:
	_token_label.text = _actor.tokens.get_display_text()

func set_inactive() -> void:
	modulate.a = 0.5

func nudge(enabled: bool) -> void:
	var target_y: float = NUDGE_AMOUNT if enabled else 0.0
	var tween := create_tween()
	tween.tween_property(self, "offset_top", -target_y, NUDGE_DURATION)
```

- [ ] **Step 4: Update `EnemyCard.gd`**

```gdscript
class_name EnemyCard
extends Control

const NUDGE_AMOUNT: float = 12.0
const NUDGE_DURATION: float = 0.12

@onready var hp_bar: TextureProgressBar = $VBox/TopBar/HPBar
@onready var mp_bar: TextureProgressBar = $VBox/TopBar/MPBar
@onready var ap_bar: TextureProgressBar = $VBox/APBar
@onready var _token_label: Label = $VBox/TokenContainer/TokenLabel

var _actor: CombatCharacter = null

func setup(actor: CombatCharacter) -> void:
	_actor = actor
	hp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxHP)
	mp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxMP)
	ap_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxAP)
	actor.vitals.vitals_changed.connect(refresh_vitals)
	actor.tokens.token_added.connect(_refresh_token_display)
	actor.tokens.token_removed.connect(_refresh_token_display)
	refresh_vitals()

func refresh_vitals() -> void:
	if _actor == null:
		return
	hp_bar.value = _actor.vitals.cur_hp
	mp_bar.value = _actor.vitals.cur_mp
	ap_bar.value = _actor.vitals.cur_ap

func _refresh_token_display(_token = null) -> void:
	_token_label.text = _actor.tokens.get_display_text()

func set_inactive() -> void:
	modulate.a = 0.5

func nudge(enabled: bool) -> void:
	var target_y: float = NUDGE_AMOUNT if enabled else 0.0
	var tween := create_tween()
	tween.tween_property(self, "offset_top", target_y, NUDGE_DURATION)
```

- [ ] **Step 5: Verify in Godot**

Open Godot. Check Output — no errors. Run the combat scene. Confirm cards load without crashing. Token labels start empty.

- [ ] **Step 6: Commit**

```bash
git add scripts/combat/ui/PlayerCard.gd scripts/combat/ui/EnemyCard.gd
git add scenes/combat/ui/player_card.tscn scenes/combat/ui/enemy_card.tscn
git commit -m "feat: PlayerCard and EnemyCard show active token display via ActiveTokens signals"
```

---

## Task 12: Author Viper Strike and verify end-to-end

**Files:**
- Create: `resources/mnemonics/viper_strike/` (new folder, files authored in Godot Inspector)

This task is done entirely in the Godot editor. No code to write.

### Part A — Effect resources

- [ ] **Step 1: Create the Pierce damage effect**

In the Godot FileSystem dock, right-click `resources/mnemonics/` → New Folder → `viper_strike`.

Right-click `resources/mnemonics/viper_strike/` → New Resource → `Skill_Effect_Damage`. Set:
- `power`: 25
- `damage_type`: Pierce
- `inherit_from_weapon`: false (viper fangs — not weapon-driven)
- `chance_tier`: HIGH
- `crit_chance`: 5
- `needs_previous_hit`: false
- `true_strike`: false

Save as `resources/mnemonics/viper_strike/effect_pierce_25.tres`.

- [ ] **Step 2: Create the POISON DoT effect**

New Resource → `Skill_Effect_DoT`. Set:
- `dot_tag`: POISON
- `charges`: 3
- `needs_previous_hit`: true ← gates the DoT on the Pierce step hitting

Save as `resources/mnemonics/viper_strike/effect_poison_3.tres`.

### Part B — Targeting and Mnemonic

- [ ] **Step 3: Reuse existing targeting resource**

Viper Strike targets a single enemy — use the existing `resources/mnemonics/targeting_single_enemy.tres`. No new file needed.

- [ ] **Step 4: Create the MnemonicResource**

New Resource → `MnemonicResource`. Set:
- `mnemonic_name`: "Viper Strike"
- `ap_cost`: 1
- `mp_cost`: 0
- `hp_cost_percent`: 0.0
- `rank`: 1
- `is_melee`: true
- `merge_display`: false (Pierce and POISON are separate — show each number independently)
- `targeting`: load `targeting_single_enemy.tres`
- `effect_steps`: add `effect_pierce_25.tres` first, then `effect_poison_3.tres`

Save as `resources/mnemonics/viper_strike/viper_strike.tres`.

- [ ] **Step 5: Assign to a player character**

Open Skugge's PlayerData `.tres` under `resources/characters/`. In the `Mnemonics` array, add `viper_strike.tres` alongside the existing mnemonic.

### Part C — End-to-end verification

- [ ] **Step 6: Run the combat scene and verify all five conditions**

Run the scene (F5). Walk through:

1. **Pierce hits — POISON attaches:** Use Viper Strike when it lands. Check Output for `RuntimeToken_Damage` hit line. Check enemy card — `POISON×3` should appear in the token label.

2. **Pierce misses — POISON does NOT attach:** Observe a miss (or temporarily set dodge very high on the enemy resource). Check Output for `RuntimeToken_Damage — missed`. Confirm `POISON` does NOT appear on enemy card.

3. **POISON ticks on enemy TurnStart:** After POISON is applied, wait for the enemy's turn. Check Output for `RuntimeToken_DoT tick [enemy] POISON N dmg`. A damage number should appear. The label should show `POISON×2`.

4. **POISON expires after 3 ticks:** After three enemy turns with POISON active, check Output for `ActiveTokens — expired`. The token label should clear.

5. **Existing mnemonics unchanged:** Skugge's Tergo Lupi and the enemy's Strike should still work identically to before.

- [ ] **Step 7: Commit**

```bash
git add resources/mnemonics/viper_strike/
git commit -m "feat: Viper Strike mnemonic authored — Pierce + POISON DoT, pipeline verified end-to-end"
```

---

## Self-Review

### Spec coverage

- [x] `RuntimeToken` base class — Task 4
- [x] `RuntimeToken_Damage` (INSTANT) — Task 6
- [x] `RuntimeToken_DoT` (ON_TURN_START) — Task 7
- [x] `Skill_Effect_DoT` resource — Task 3
- [x] `ActionContext.record_step()` + `tokens_applied` — Task 5
- [x] `any_hit` only set by instant hits — enforced in `record_step()`, Task 5
- [x] `ActiveTokens` full implementation — Task 8
- [x] `SkillExecutor` rewrite as factory, receives context — Task 9
- [x] `CombatFSM` creates ActionContext before SkillExecutor — Task 10
- [x] `CombatFSM` TurnStart ticking — already wired on line 50, `tick_turn_start()` now implemented in Task 8
- [x] Token display on PlayerCard and EnemyCard — Task 11
- [x] Viper Strike authored and verified — Task 12
- [x] `max_mp` public for POISON formula — Task 1
- [x] `dot_ticked` signal — Task 2
- [x] Deferred triggers (ON_DAMAGE_TAKEN, ON_ALLY_HIT, PRE_EXECUTION) — documented in `RuntimeToken.Trigger` enum stubs, Task 4

### Notes for implementor

- `CombatCharacter` uses `tokens` (not `active_tokens`) — confirmed from source
- Both card `.tscn` files already have `TokenContainer` (HBoxContainer) — the slot exists, just needs the Label child
- `VitalsComponent._max_mp` is private in the current codebase — Task 1 must run before Task 7
- SkillExecutor's `execute()` return type changed from `ActionContext` to `void` — the context is passed in and mutated. CombatFSM holds the reference and reads it after the call.
- The `Skill_Effect_Base` preload in the old SkillExecutor is no longer needed — removed in rewrite
