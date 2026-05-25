# Combat Pipeline Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the missing COUNTER damage multiplier bug and eliminate six code duplication smells in the combat pipeline without changing observable behaviour.

**Architecture:** All damage resolution logic consolidates into two new static functions on `CombatCalculator` (`is_physical` and `resolve_hit`). The three token files become thin callers. `ActiveTokens` extracts a private `_tick_trigger` to unify its two near-identical tick methods. `ActionPipeline` moves its reaction queue arrays out of `ActionContext` (where they don't belong) and extracts a `_run_reaction_pass` helper.

**Tech Stack:** GDScript, Godot 4.6 — no new files, no new classes, no new dependencies.

---

## File Map

| File | Change |
|---|---|
| `scripts/combat/CombatCalculator.gd` | Add `is_physical()` + `resolve_hit()` |
| `scripts/combat/tokens/RuntimeToken_Damage.gd` | Use `resolve_hit()`, remove `_is_physical()` |
| `scripts/combat/tokens/RuntimeToken_Envenom.gd` | Use `resolve_hit()`, remove `_is_physical()` |
| `scripts/combat/tokens/RuntimeToken_Counter.gd` | Use `resolve_hit()` — multiplier bug fixed for free |
| `scripts/combat/ActiveTokens.gd` | Extract `_tick_trigger()`, simplify both tick methods |
| `scripts/combat/ActionContext.gd` | Remove `pre_queue` and `post_queue` |
| `scripts/combat/ActionPipeline.gd` | Local queue vars, extract `_run_reaction_pass()` |
| `scripts/combat/tokens/RuntimeToken_Stun.gd` | Add comment to clarify dead trigger value |

---

## Task 1: Add `is_physical` and `resolve_hit` to CombatCalculator

**Files:**
- Modify: `scripts/combat/CombatCalculator.gd`

- [ ] **Step 1: Open the file and read the current state**

  Read `scripts/combat/CombatCalculator.gd`. It currently has four static functions: `calc_damage`, `crit_roll`, `hit_roll`, `resist_multiplier`, and a private `_tier_multiplier`. No imports of `CombatCharacter` or `CharacterStats` — those are resolved globally via `class_name`.

- [ ] **Step 2: Add `is_physical` after `resist_multiplier`**

  The two `_is_physical` copies in Damage and Envenom use different syntaxes (or-chain vs in-array). Canonical version uses `in` array. Add before `_tier_multiplier`:

  ```gdscript
  static func is_physical(dt: ResistanceType.DamageType) -> bool:
  	return dt in [ResistanceType.DamageType.Slash, ResistanceType.DamageType.Pierce, ResistanceType.DamageType.Blunt]
  ```

- [ ] **Step 3: Add `resolve_hit` after `is_physical`**

  This replaces the ~20-line hit→crit→stat→calc→resist→mult pipeline copy-pasted across three token files. Returns a dict so the caller can read `hit`, `damage`, `is_crit`, and `multiplier` for logging.

  Note: `source.tokens.get_damage_multiplier()` is called inside — this is the one place COUNTER was missing it. All three callers now get multiplier automatically.

  ```gdscript
  ## Full hit-crit-damage pipeline. Returns {hit, damage, is_crit, multiplier}.
  ## Rolls crit first, then hit (skipped for magic or true_strike), then resolves
  ## stats, resist, and the source's active damage multiplier tokens.
  static func resolve_hit(
  		power: int,
  		damage_type: ResistanceType.DamageType,
  		crit_chance: int,
  		chance_tier: SkillEffectBase.ChanceTier,
  		source: CombatCharacter,
  		target: CombatCharacter,
  		true_strike: bool = false
  ) -> Dictionary:
  	var phys := is_physical(damage_type)
  	var is_crit := phys and crit_roll(crit_chance)

  	if phys and not is_crit and not true_strike:
  		var hit := source.stats.stat(CharacterStats.Stat.Hit)
  		var dodge := target.stats.stat(CharacterStats.Stat.Dodge)
  		if not hit_roll(hit, dodge, chance_tier):
  			return {hit = false, damage = 0, is_crit = false, multiplier = 1.0}

  	var atk_stat := CharacterStats.Stat.AtkPhys if phys else CharacterStats.Stat.AtkMag
  	var def_stat := CharacterStats.Stat.DefPhys if phys else CharacterStats.Stat.DefMag
  	var raw := calc_damage(power, source.stats.stat(atk_stat), target.stats.stat(def_stat))

  	if is_crit:
  		raw *= 2

  	var resist := ResistanceType.State.NONE
  	if target.resistance_profile != null:
  		resist = target.resistance_profile.get_state(damage_type)

  	var mult := source.tokens.get_damage_multiplier()
  	var final := max(0, int(raw * resist_multiplier(resist) * mult))
  	return {hit = true, damage = final, is_crit = is_crit, multiplier = mult}
  ```

- [ ] **Step 4: Validate the script in Godot**

  Open the MCP tool and call `validate_script` on `scripts/combat/CombatCalculator.gd`. Expected: no errors.

- [ ] **Step 5: Commit**

  ```bash
  git add scripts/combat/CombatCalculator.gd
  git commit -m "feat: add is_physical and resolve_hit to CombatCalculator"
  ```

---

## Task 2: Refactor RuntimeToken_Damage

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Damage.gd`

- [ ] **Step 1: Replace the file body**

  The resist state is no longer available for the log line (it's internal to `resolve_hit`). This is an intentional simplification — the final damage already reflects resist, and the log is still useful.

  Full replacement:

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

  func _init() -> void:
  	token_type = "DAMAGE"
  	trigger = Trigger.INSTANT

  func fire(context: ActionContext) -> void:
  	var effective_type := damage_type
  	if CombatCalculator.is_physical(damage_type) and inherit_from_weapon:
  		effective_type = _get_weapon_damage_type()

  	var result := CombatCalculator.resolve_hit(power, effective_type, crit_chance, chance_tier, source, owner, true_strike)

  	if not result.hit:
  		Log.info("RuntimeToken_Damage — missed", "%s->%s" % [source.character_name, owner.character_name])
  		CombatEvents.combat_text_shown.emit(owner, "MISS")
  		context.record_step(false, 0, false)
  		return

  	var mult_str := "" if result.multiplier == 1.0 else " mult:%.2f" % result.multiplier
  	Log.info("RuntimeToken_Damage", "%s->%s %d (crit:%s%s)" % [
  		source.character_name, owner.character_name, result.damage, result.is_crit, mult_str])

  	owner.vitals.take_damage(result.damage)
  	CombatEvents.action_executed.emit(source, owner, result.damage)
  	context.record_step(true, result.damage, result.is_crit)

  static func _get_weapon_damage_type() -> ResistanceType.DamageType:
  	# TODO: read from attacker's equipped weapon once gear system exists.
  	return ResistanceType.DamageType.Slash
  ```

- [ ] **Step 2: Validate**

  `validate_script` on `scripts/combat/tokens/RuntimeToken_Damage.gd`. Expected: no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add scripts/combat/tokens/RuntimeToken_Damage.gd
  git commit -m "refactor: RuntimeToken_Damage uses CombatCalculator.resolve_hit"
  ```

---

## Task 3: Refactor RuntimeToken_Envenom

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Envenom.gd`

- [ ] **Step 1: Replace the file body**

  `power_per_token * count` becomes the `power` argument. The `_is_physical` static copy is removed.

  ```gdscript
  class_name RuntimeToken_Envenom
  extends RuntimeToken

  const ActionContext = preload("res://scripts/combat/ActionContext.gd")

  @export var consume_type: String = "POISON"
  @export var power_per_token: int = 30
  @export var damage_type: ResistanceType.DamageType = ResistanceType.DamageType.Nature
  @export var crit_chance: int = 5
  @export var chance_tier: Skill_Effect_Base.ChanceTier = Skill_Effect_Base.ChanceTier.HIGH

  func _init() -> void:
  	token_type = "ENVENOM"
  	trigger = Trigger.INSTANT

  func fire(context: ActionContext) -> void:
  	var count := owner.tokens.consume_all(consume_type)
  	if count == 0:
  		Log.warn("RuntimeToken_Envenom — no tokens", owner.character_name)
  		context.record_step(false, 0, false)
  		return

  	var result := CombatCalculator.resolve_hit(
  		count * power_per_token, damage_type, crit_chance, chance_tier, source, owner)

  	if not result.hit:
  		Log.info("RuntimeToken_Envenom — missed", source.character_name, owner.character_name)
  		CombatEvents.combat_text_shown.emit(owner, "MISS")
  		context.record_step(false, 0, false)
  		return

  	var mult_str := "" if result.multiplier == 1.0 else " mult:%.2f" % result.multiplier
  	Log.info("RuntimeToken_Envenom", "%s->%s %d×%d=%d (crit:%s%s)" % [
  		source.character_name, owner.character_name,
  		count, power_per_token, result.damage, result.is_crit, mult_str])

  	owner.vitals.take_damage(result.damage)
  	CombatEvents.action_executed.emit(source, owner, result.damage)
  	context.record_step(true, result.damage, result.is_crit)
  ```

- [ ] **Step 2: Validate**

  `validate_script` on `scripts/combat/tokens/RuntimeToken_Envenom.gd`. Expected: no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add scripts/combat/tokens/RuntimeToken_Envenom.gd
  git commit -m "refactor: RuntimeToken_Envenom uses CombatCalculator.resolve_hit"
  ```

---

## Task 4: Refactor RuntimeToken_Counter and fix the multiplier bug

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken_Counter.gd`

This task fixes the bug where a COUNTER attacker with EMPOWER (or WEAKEN debuff) did not have their multiplier applied. The fix comes for free: `resolve_hit` calls `source.tokens.get_damage_multiplier()` internally, and here `source` is `owner` (the counter-attacking character).

- [ ] **Step 1: Replace the file body**

  ```gdscript
  class_name RuntimeToken_Counter
  extends RuntimeToken

  @export var power: int = 15

  func _init() -> void:
  	trigger = Trigger.ON_DAMAGE_TAKEN
  	token_type = "COUNTER"

  func check_trigger(context: ActionContext) -> bool:
  	return context.target == owner and not context.step_results.is_empty()

  func fire(context: ActionContext) -> void:
  	var attacker: CombatCharacter = context.trigger_context.source
  	var result := CombatCalculator.resolve_hit(
  		power,
  		ResistanceType.DamageType.Slash,
  		5,
  		Skill_Effect_Base.ChanceTier.HIGH,
  		owner,
  		attacker
  	)

  	if not result.hit:
  		Log.info("RuntimeToken_Counter — missed", owner.character_name)
  		CombatEvents.combat_text_shown.emit(attacker, "MISS")
  		return

  	Log.info("RuntimeToken_Counter", "%s->%s %d (crit:%s)" % [
  		owner.character_name, attacker.character_name, result.damage, result.is_crit])
  	attacker.vitals.take_damage(result.damage)
  	CombatEvents.action_executed.emit(owner, attacker, result.damage)
  ```

- [ ] **Step 2: Validate**

  `validate_script` on `scripts/combat/tokens/RuntimeToken_Counter.gd`. Expected: no errors.

- [ ] **Step 3: Manual smoke test**

  Run the game. Put Skugge (who has Counter Stance) in a fight. Have an enemy hit Skugge. Confirm the COUNTER fires: the enemy takes damage, a damage number appears on the enemy, and the combat log shows `RuntimeToken_Counter` with `->` between character names.

  If you have EMPOWER available, grant it to Skugge before testing — the counter hit should be noticeably stronger than without it. Without EMPOWER equipped, the fix is invisible but the pipeline is correct.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/combat/tokens/RuntimeToken_Counter.gd
  git commit -m "fix: RuntimeToken_Counter now applies source damage multiplier via resolve_hit"
  ```

---

## Task 5: Extract `_tick_trigger` in ActiveTokens

**Files:**
- Modify: `scripts/combat/ActiveTokens.gd`

`tick_turn_start` and `tick_turn_end` are ~85% identical. The only real difference was the `skip_first_tick` branch, which only ON_TURN_END tokens ever set. Including the check in the unified method is safe for ON_TURN_START tokens — they never set `skip_first_tick`, so the branch never fires.

- [ ] **Step 1: Replace `tick_turn_start` (lines 35–52) with a one-liner**

  ```gdscript
  func tick_turn_start() -> void:
  	_tick_trigger(RuntimeToken.Trigger.ON_TURN_START)
  ```

- [ ] **Step 2: Replace `tick_turn_end` (lines 83–104) with a one-liner**

  ```gdscript
  func tick_turn_end() -> void:
  	_tick_trigger(RuntimeToken.Trigger.ON_TURN_END)
  ```

- [ ] **Step 3: Add `_tick_trigger` after `tick_turn_end`**

  ```gdscript
  func _tick_trigger(trigger: RuntimeToken.Trigger) -> void:
  	var fired_types: Array[String] = []
  	var to_tick: Array[RuntimeToken] = []

  	for token in _tokens:
  		if token.trigger != trigger:
  			continue
  		if token.token_type in fired_types:
  			continue
  		fired_types.append(token.token_type)
  		to_tick.append(token)

  	for token in to_tick:
  		if token.skip_first_tick:
  			token.skip_first_tick = false
  			Log.info("ActiveTokens — cast turn free", token.owner.character_name, token.token_type)
  			continue
  		var ctx := ActionContext.new()
  		token.tick(ctx)
  		_tokens.erase(token)
  		Log.info("ActiveTokens — expired", token.owner.character_name, token.token_type)
  		token_removed.emit(token)
  ```

- [ ] **Step 4: Validate**

  `validate_script` on `scripts/combat/ActiveTokens.gd`. Expected: no errors.

- [ ] **Step 5: Manual smoke test**

  Run the game. Enter combat. Apply a POISON or BURN DoT to a character. Advance turns. Confirm the token ticks and expires correctly (damage number on tick, token disappears from card display after expiry).

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/combat/ActiveTokens.gd
  git commit -m "refactor: extract _tick_trigger to unify tick_turn_start/end in ActiveTokens"
  ```

---

## Task 6: ActionContext cleanup + ActionPipeline `_run_reaction_pass` + Stun comment

**Files:**
- Modify: `scripts/combat/ActionContext.gd`
- Modify: `scripts/combat/ActionPipeline.gd`
- Modify: `scripts/combat/tokens/RuntimeToken_Stun.gd`

These three changes are bundled because they touch the same two-system boundary and share a commit.

- [ ] **Step 1: Remove `pre_queue` and `post_queue` from ActionContext**

  In `ActionContext.gd`, delete lines 28–32 (the two comment + two var declarations):

  ```gdscript
  # Populated by ActionPipeline pre-pass. Holds RuntimeToken objects that fire before primary.
  var pre_queue: Array = []

  # Populated by ActionPipeline post-pass. Holds RuntimeToken objects that fire after primary.
  var post_queue: Array = []
  ```

  ActionContext after this change ends at `func record_step`.

- [ ] **Step 2: Validate ActionContext**

  `validate_script` on `scripts/combat/ActionContext.gd`. Expected: no errors.

- [ ] **Step 3: Rewrite ActionPipeline**

  Replace the full content of `ActionPipeline.gd`. Changes:
  - `pre_queue` and `post_queue` become local `Array` variables in `run()`
  - Both reaction loops extracted into `_run_reaction_pass(tokens, context, announce)`
  - Log message for downed-in-reaction is unified to "(reaction)" instead of "(pre-reaction)"/"(post-reaction)"

  ```gdscript
  class_name ActionPipeline
  extends Node

  signal pipeline_complete

  const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

  func run(mnemonic: MnemonicRes, attacker: CombatCharacter, target: CombatCharacter, actors: Array) -> void:
  	if mnemonic == null or attacker == null or target == null:
  		Log.error("ActionPipeline.run — invalid inputs", mnemonic, attacker)
  		pipeline_complete.emit()
  		return

  	var context := ActionContext.new()
  	context.mnemonic = mnemonic
  	context.source = attacker
  	context.target = target

  	CombatEvents.action_announced.emit(mnemonic.mnemonic_name)
  	await get_tree().create_timer(0.5).timeout

  	var pre_tokens: Array = []
  	for actor: CombatCharacter in actors:
  		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.PRE_EXECUTION):
  			pre_tokens.append(token)
  	await _run_reaction_pass(pre_tokens, context, false)

  	if not _can_execute(context):
  		if context.negated:
  			Log.info("ActionPipeline — primary action negated")
  		elif context.cancelled:
  			Log.info("ActionPipeline — primary action cancelled")
  		CombatEvents.action_resolved.emit(context)
  		pipeline_complete.emit()
  		return

  	attacker.vitals.spend_ap(mnemonic.ap_cost)
  	attacker.vitals.spend_mp(mnemonic.mp_cost)

  	if mnemonic.is_melee:
  		var target_slot_pos: Vector3 = target.get_parent().global_position
  		await attacker.visuals.approach(target_slot_pos)

  	SkillExecutor.execute(context)

  	if mnemonic.is_melee:
  		await attacker.visuals.recover()

  	if mnemonic.hp_cost_percent > 0.0:
  		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)

  	if context.target.vitals.is_downed():
  		Log.info("ActionPipeline — downed", context.target.character_name)
  		CombatEvents.actor_downed.emit(context.target)

  	await get_tree().create_timer(0.4).timeout

  	var post_tokens: Array = []
  	for actor: CombatCharacter in actors:
  		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_DAMAGE_TAKEN):
  			post_tokens.append(token)
  		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_ALLY_HIT):
  			post_tokens.append(token)
  	await _run_reaction_pass(post_tokens, context, true)

  	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
  		attacker.character_name, context.target.character_name, context.total_damage])
  	CombatEvents.action_resolved.emit(context)
  	pipeline_complete.emit()

  func _run_reaction_pass(tokens: Array, context: ActionContext, announce: bool) -> void:
  	for token in tokens:
  		if announce:
  			CombatEvents.action_announced.emit(token.token_type)
  			await get_tree().create_timer(0.5).timeout
  		var reaction_ctx := ActionContext.new()
  		reaction_ctx.trigger_context = context
  		token.fire(reaction_ctx)
  		token.owner.tokens.remove_token(token)
  		if reaction_ctx.target != null and reaction_ctx.target.vitals.is_downed():
  			Log.info("ActionPipeline — downed (reaction)", reaction_ctx.target.character_name)
  			CombatEvents.actor_downed.emit(reaction_ctx.target)

  ## Validation rules, in order:
  ## 1. Source downed → cancelled (no resource cost)
  ## 2. Source stunned/silenced/frozen → cancelled (no resource cost)
  ## 3. Action negated by PRE reaction → negated (resource cost IS spent)
  ## 4. Insufficient AP/MP after pre-reactions → cancelled (no resource cost)
  func _can_execute(context: ActionContext) -> bool:
  	var attacker: CombatCharacter = context.source

  	if attacker.vitals.is_downed():
  		context.cancelled = true
  		return false

  	if context.negated:
  		return false

  	if attacker.vitals.cur_ap < context.mnemonic.ap_cost \
  			or attacker.vitals.cur_mp < context.mnemonic.mp_cost:
  		context.cancelled = true
  		return false

  	return true
  ```

- [ ] **Step 4: Validate ActionPipeline**

  `validate_script` on `scripts/combat/ActionPipeline.gd`. Expected: no errors.

- [ ] **Step 5: Fix Stun dead-code trigger**

  In `RuntimeToken_Stun.gd`, add a comment explaining the trigger value is unused:

  ```gdscript
  class_name RuntimeToken_Stun
  extends RuntimeToken

  func _init() -> void:
  	trigger = Trigger.INSTANT  # unused — STUN is consumed manually by CombatFSM, not the trigger system
  	token_type = "STUN"
  ```

- [ ] **Step 6: Manual smoke test**

  Run the game. Trigger a full combat round:
  - Use a mnemonic that triggers a COUNTER reaction — confirm the reaction still fires and announces.
  - Use a mnemonic against a character with STUN — confirm the stunned turn is still skipped.
  - Check the Godot console: no errors, no warnings from ActionPipeline.

- [ ] **Step 7: Commit**

  ```bash
  git add scripts/combat/ActionContext.gd scripts/combat/ActionPipeline.gd scripts/combat/tokens/RuntimeToken_Stun.gd
  git commit -m "refactor: move reaction queues out of ActionContext, extract _run_reaction_pass, clarify Stun trigger"
  ```
