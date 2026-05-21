# Action Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bloated `_enter_action_execution` FSM handler with a dedicated `ActionPipeline` node that owns the full action resolution cycle — announce, pre-execution reactions, primary execution, post-execution reactions — while trimming CombatFSM to a pure state pump.

**Architecture:** `ActionPipeline` is a sibling Node under `CombatScene`. `CombatFSM` calls `pipeline.run()` and awaits `pipeline_complete`. Token self-selection uses **direct iteration** — ActionPipeline loops over all actors' token lists and calls `check_trigger(context)` on each reaction token. No signal connections, no connect/disconnect lifecycle. `ActionContext` gains two queue arrays (`pre_queue`, `post_queue`) that hold `RuntimeToken` objects. Today those queues are always empty — the mechanism is wired, reaction tokens are future work.

**Tech Stack:** GDScript, Godot 4.6, Godot MCP tools for scene manipulation.

---

## First Principles — What Is (and Is Not) a Reaction

Not every token that responds to combat activity is a "reaction." The pipeline's PRE/POST passes are for tokens that genuinely need a **before/after window** around the primary action. Everything else is just **passive state** that damage resolution reads inline.

| Token | Type | Where It Lives | Why |
|---|---|---|---|
| **COVER / INTERCEPT** | Passive | `RuntimeToken_Damage.fire()` — target resolution step | Effects aimed at the protectee always redirect to the protector. No window needed. COVERED/COVERING pair consumed on redirect. AoE dedup: if protector already absorbed a covering hit this action, their own direct AoE slot is skipped — protector takes 1 hit total. |
| **BRACE / Shield** | Passive | `RuntimeToken_Damage.fire()` — damage calc step | "Reduce damage by X%" modifies the number. Checked inline, no window. |
| **COUNTER** | POST reaction | ActionPipeline post-pass | "If you hit me, I hit back" needs the primary to resolve first (to know if it hit), then fires after. |
| **HAMEDO** | PRE reaction | ActionPipeline pre-pass | "Hit first before they hit you" needs to fire before the primary resolves, and may kill the attacker to cancel the action. |
| **PREMONITION** | PRE reaction | ActionPipeline pre-pass | "Nullify an incoming spell" fires before execution and sets `context.negated = true`. |
| **VIGIL** | POST reaction | ActionPipeline post-pass | "When an ally takes damage, heal them" needs the primary to resolve (to know who was hurt and for how much). |
| **FOLLOW UP** | POST reaction | ActionPipeline post-pass | "When an ally hits an enemy, I hit too" same window as VIGIL. |

**Rule:** If the effect can be described as "modify how Z works" or "redirect from A to B," it's passive state. If it's "when X happens, do Y," it's a reaction that belongs in a pass.

### COVER / INTERCEPT — Design Notes

- **Protectee is always a valid target.** Nothing prevents the covered character from being selected by AI or player. The redirect happens at effect application time, not at target selection time.
- **Redirect is universal.** Single-target or AoE, the rule is identical: if effects would land on the protectee, they land on the protector instead. Token pair consumed on redirect.
- **AoE dedup.** If the protector is also in the AoE blast, they take 1 hit total — not 2. Track a `hits_received` set per action execution. Before applying damage to a resolved target, check the set. If already hit, skip. Add to set after applying.
- **Downed protector cleanup (Option B — eager).** `RuntimeToken_Covered` subscribes to `CombatEvents.actor_downed` in its own `_ready()`. When the downed actor matches its protector, the token removes itself from the protectee's `ActiveTokens` immediately. No stale protection state.
- **Charge consumption.** COVERED/COVERING are always a pair. Each covering intercept consumes one pair. Multiple pairs = multiple uses.

---

## File Map

| Action | Path |
|---|---|
| **Create** | `scripts/combat/ActionPipeline.gd` |
| **Create** | `scenes/combat/components/action_pipeline.tscn` |
| **Modify** | `scripts/combat/tokens/RuntimeToken.gd` |
| **Modify** | `scripts/combat/ActiveTokens.gd` |
| **Modify** | `scripts/combat/ActionContext.gd` |
| **Modify** | `scripts/combat/CombatEvents.gd` |
| **Modify** | `scripts/combat/CombatFSM.gd` |
| **Modify** | `scripts/combat/CombatScene.gd` |
| **Modify** | `scenes/combat/combat_scene.tscn` (via Godot MCP) |

---

## Task 1: Prepare RuntimeToken and ActiveTokens for direct iteration

**Files:**
- Modify: `scripts/combat/tokens/RuntimeToken.gd`
- Modify: `scripts/combat/ActiveTokens.gd`

- [ ] **Step 1: Add check_trigger stub to RuntimeToken**

Open `scripts/combat/tokens/RuntimeToken.gd`. The file currently ends with:

```gdscript
## Called by ActiveTokens.tick_turn_start() for ON_TURN_START tokens.
## ActiveTokens creates one fresh context per token before calling this.
## mnemonic/attacker/primary_target are null on that context — read self.owner/self.source instead.
func tick(_context: ActionContext) -> void:
	pass
```

Add this method after `tick()`:

```gdscript
## Override in reaction token subclasses to declare trigger conditions.
## Called by ActiveTokens.collect_triggers() during ActionPipeline pre/post passes.
## Must return synchronously — no await. This is a condition check, not a firing step.
func check_trigger(_context: ActionContext) -> bool:
	return false
```

- [ ] **Step 2: Add collect_triggers to ActiveTokens**

Open `scripts/combat/ActiveTokens.gd`. Add this method before `flush()`:

```gdscript
## Returns all tokens whose trigger matches and whose check_trigger passes for this context.
## Called by ActionPipeline during pre and post passes. Safe to call with an empty token list.
func collect_triggers(context: ActionContext, trigger: RuntimeToken.Trigger) -> Array:
	var result: Array = []
	for token in _tokens:
		if token.trigger == trigger and token.check_trigger(context):
			result.append(token)
	return result
```

- [ ] **Step 3: Verify the scene runs clean**

Use the Godot MCP tool `get_errors` or run the scene (F5 in editor). Expected: zero new errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/tokens/RuntimeToken.gd scripts/combat/ActiveTokens.gd
git commit -m "feat: add check_trigger stub to RuntimeToken and collect_triggers to ActiveTokens"
```

---

## Task 2: Extend ActionContext with execution queues

**Files:**
- Modify: `scripts/combat/ActionContext.gd`

- [ ] **Step 1: Add queue fields to ActionContext**

Open `scripts/combat/ActionContext.gd`. Replace the whole file with:

```gdscript
class_name ActionContext
extends RefCounted

const MnemonicResource = preload("res://scripts/combat/skills/MnemonicResource.gd")

var mnemonic: MnemonicResource
var attacker: CombatCharacter
var primary_target: CombatCharacter

var step_results: Array = []
var tokens_applied: Array = []
var total_damage: int = 0
var any_hit: bool = false
var any_crit: bool = false

# Reference to the primary action's context. Set on reaction contexts so tokens
# can read the triggering event for target resolution (e.g. COUNTER hits the attacker).
var trigger_context: ActionContext = null

# Set by PRE_EXECUTION reactions (e.g. Premonition) to nullify the primary action.
# ActionPipeline checks this after the pre-pass and skips SkillExecutor if true.
var negated: bool = false

# Set by ActionPipeline when validation fails (attacker downed, stunned, etc.).
# Used for UI feedback — "cancelled" is distinct from "negated" (no resource cost).
var cancelled: bool = false

# Populated by ActionPipeline pre-pass. Holds RuntimeToken objects that fire before primary.
var pre_queue: Array = []

# Populated by ActionPipeline post-pass. Holds RuntimeToken objects that fire after primary.
var post_queue: Array = []

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

- [ ] **Step 2: Verify the scene runs clean**

Run the scene or use `get_errors`. Expected: zero new errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ActionContext.gd
git commit -m "feat: add pre_queue, post_queue, and trigger_context to ActionContext for reaction pipeline"
```

---

## Task 3: Create ActionPipeline.gd

**Files:**
- Create: `scripts/combat/ActionPipeline.gd`

- [ ] **Step 1: Create the file**

Create `scripts/combat/ActionPipeline.gd` with the following content:

```gdscript
class_name ActionPipeline
extends Node

signal pipeline_complete

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

func run(mnemonic: MnemonicRes, attacker: CombatCharacter, target: CombatCharacter, actors: Array) -> void:
	# Front-loaded null guard — validate before entering async territory.
	# If anything is missing here, pipeline_complete still fires so the FSM never hangs.
	if mnemonic == null or attacker == null or target == null:
		Log.error("ActionPipeline.run — invalid inputs", mnemonic, attacker, target)
		pipeline_complete.emit()
		return

	var context := ActionContext.new()
	context.mnemonic = mnemonic
	context.attacker = attacker
	context.primary_target = target

	# Announce and hold for presentation
	CombatEvents.action_announced.emit(mnemonic.mnemonic_name)
	await get_tree().create_timer(0.5).timeout

	# PRE-PASS: direct iteration over all actors' tokens.
	# Each reaction fires with its own clean context. trigger_context points to the primary.
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.PRE_EXECUTION):
			context.pre_queue.append(token)
	for token in context.pre_queue:
		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		token.fire(reaction_ctx)
		if reaction_ctx.primary_target != null and reaction_ctx.primary_target.vitals.is_downed():
			Log.info("ActionPipeline — downed (pre-reaction)", reaction_ctx.primary_target.character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.primary_target)

	# VALIDATE: can the attacker still execute after pre-reactions?
	if not _can_execute(context):
		if context.negated:
			Log.info("ActionPipeline — primary action negated")
		elif context.cancelled:
			Log.info("ActionPipeline — primary action cancelled")
		CombatEvents.action_resolved.emit(context)
		pipeline_complete.emit()
		return

	# Spend resources — only after validation confirms the action will resolve
	attacker.vitals.spend_ap(mnemonic.ap_cost)
	attacker.vitals.spend_mp(mnemonic.mp_cost)

	# Primary action
	SkillExecutor.execute(context)

	# HP blood cost — paid after execution, not before (it's a price, not a prerequisite)
	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)

	# Downed detection for primary target
	if context.primary_target.vitals.is_downed():
		Log.info("ActionPipeline — downed", context.primary_target.character_name)
		CombatEvents.actor_downed.emit(context.primary_target)

	# POST-PASS: direct iteration with updated context (any_hit, total_damage, etc. are set).
	# Each reaction fires with its own clean context. trigger_context points to the primary.
	for actor: CombatCharacter in actors:
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_DAMAGE_TAKEN):
			context.post_queue.append(token)
		for token in actor.tokens.collect_triggers(context, RuntimeToken.Trigger.ON_ALLY_HIT):
			context.post_queue.append(token)
	for token in context.post_queue:
		var reaction_ctx := ActionContext.new()
		reaction_ctx.trigger_context = context
		token.fire(reaction_ctx)
		if reaction_ctx.primary_target != null and reaction_ctx.primary_target.vitals.is_downed():
			Log.info("ActionPipeline — downed (post-reaction)", reaction_ctx.primary_target.character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.primary_target)

	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
		attacker.character_name, context.primary_target.character_name, context.total_damage])
	CombatEvents.action_resolved.emit(context)
	pipeline_complete.emit()

## Validation rules, in order:
## 1. Attacker downed → cancelled (no resource cost)
## 2. Attacker stunned/silenced/frozen → cancelled (no resource cost)
## 3. Action negated by PRE reaction → negated (resource cost IS spent)
## 4. Insufficient AP/MP after pre-reactions → cancelled (no resource cost)
func _can_execute(context: ActionContext) -> bool:
	var attacker: CombatCharacter = context.attacker

	if attacker.vitals.is_downed():
		context.cancelled = true
		return false

	# TODO: stunned, silenced, frozen checks when status ailments exist
	# if attacker.tokens.has_status("stunned") or attacker.tokens.has_status("silenced"):
	#     context.cancelled = true
	#     return false

	if context.negated:
		return false

	if attacker.vitals.cur_ap < context.mnemonic.ap_cost \
			or attacker.vitals.cur_mp < context.mnemonic.mp_cost:
		context.cancelled = true
		return false

	return true
```

- [ ] **Step 2: Update the action_resolved signal in CombatEvents.gd**

Open `scripts/combat/CombatEvents.gd`. Find:

```gdscript
signal action_resolved(actor: CombatCharacter)
```

Replace with:

```gdscript
signal action_resolved(context: ActionContext)
```

No subscribers exist yet — nothing else in the codebase currently connects to this signal, so the rename is free.

- [ ] **Step 3: Verify the scene runs clean**

Run the scene or use `get_errors`. Expected: zero new errors (pipeline not wired yet, just authored).

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/ActionPipeline.gd scripts/combat/CombatEvents.gd
git commit -m "feat: implement ActionPipeline — pre/post passes, context-carrying action_resolved, null guard"
```

---

## Task 4: Create action_pipeline.tscn and add it to CombatScene

**Files:**
- Create: `scenes/combat/components/action_pipeline.tscn` (via Godot MCP)
- Modify: `scenes/combat/combat_scene.tscn` (via Godot MCP)

- [ ] **Step 1: Create the scene file using Godot MCP**

Use the Godot MCP tool `create_scene`:

```
create_scene(
  scene_name: "action_pipeline",
  root_node_type: "Node",
  save_path: "res://scenes/combat/components/action_pipeline.tscn"
)
```

Then attach the script using `attach_script`:

```
attach_script(
  scene_path: "res://scenes/combat/components/action_pipeline.tscn",
  node_path: ".",
  script_path: "res://scripts/combat/ActionPipeline.gd"
)
```

- [ ] **Step 2: Instance ActionPipeline into CombatScene**

Use the Godot MCP tool `instance_scene` to add ActionPipeline as a child of CombatScene:

```
instance_scene(
  scene_path: "res://scenes/combat/combat_scene.tscn",
  instance_path: "res://scenes/combat/components/action_pipeline.tscn",
  parent_node_path: ".",
  node_name: "ActionPipeline"
)
```

Verify with `read_scene("res://scenes/combat/combat_scene.tscn")` that `ActionPipeline` appears as a child of the root node, sibling to `CombatFSM`.

- [ ] **Step 3: Verify the scene runs clean**

Run the scene or use `get_errors`. Expected: zero new errors.

- [ ] **Step 4: Commit**

```bash
git add scenes/combat/components/action_pipeline.tscn scenes/combat/combat_scene.tscn
git commit -m "feat: add ActionPipeline scene and instance into CombatScene"
```

---

## Task 5: Connect CombatScene and CombatFSM to ActionPipeline

**Files:**
- Modify: `scripts/combat/CombatScene.gd`
- Modify: `scripts/combat/CombatFSM.gd`

- [ ] **Step 1: Add ActionPipeline reference in CombatScene.gd and pass it to the FSM**

Open `scripts/combat/CombatScene.gd`. Replace the full file with:

```gdscript
class_name CombatScene
extends Node

@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var combat_camera: Camera3D = $Camera3D
@onready var logic_fsm: CombatFSM = $CombatFSM
@onready var ui_fsm: CombatUIFSM = $CombatUIFSM
@onready var action_pipeline: ActionPipeline = $ActionPipeline

func _clear_environment() -> void:
	for child in environment_mount.get_children():
		child.queue_free()

func initialize(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	combat_camera.make_current()
	_clear_environment()
	player_spawner.initialize()
	enemy_spawner.initialize(composition)
	if environment:
		environment_mount.add_child(environment.instantiate())
	if bgm:
		bgm_player.stream = bgm
		bgm_player.play()
	await get_tree().process_frame
	var all_actors: Array = player_spawner.get_all_characters() + enemy_spawner.get_all_characters()
	Log.info("CombatScene — actors ready:", all_actors.size())
	ui_fsm.start(all_actors)
	logic_fsm.start(all_actors, action_pipeline)
```

- [ ] **Step 2: Update CombatFSM to accept and store ActionPipeline**

Open `scripts/combat/CombatFSM.gd`. Find:

```gdscript
var _state: State = State.NONE
var _actors: Array = []
var _active_actor: CombatCharacter = null
var _pending_target: CombatCharacter = null
var _pending_mnemonic: MnemonicRes = null

func start(actors: Array) -> void:
	_actors = actors
	Log.info("CombatFSM starting with", _actors.size())
	_transition(State.COMBAT_START)
```

Replace with:

```gdscript
var _state: State = State.NONE
var _actors: Array = []
var _active_actor: CombatCharacter = null
var _pending_target: CombatCharacter = null
var _pending_mnemonic: MnemonicRes = null
var _action_pipeline: ActionPipeline = null

func start(actors: Array, pipeline: ActionPipeline) -> void:
	_actors = actors
	_action_pipeline = pipeline
	Log.info("CombatFSM starting with", _actors.size())
	_transition(State.COMBAT_START)
```

- [ ] **Step 3: Verify the scene runs clean**

Run the scene or use `get_errors`. Expected: zero new errors. Combat should still work identically — pipeline is wired but not yet called.

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/CombatScene.gd scripts/combat/CombatFSM.gd
git commit -m "feat: wire ActionPipeline reference through CombatScene into CombatFSM"
```

---

## Task 6: Trim CombatFSM — delegate execution, remove REACTION_SCAN

**Files:**
- Modify: `scripts/combat/CombatFSM.gd`

Three things happen together: `_enter_action_execution` is replaced, `REACTION_SCAN` is deleted, and `_check_combat_end` is consolidated to `TURN_END` only.

- [ ] **Step 1: Update the State enum — remove REACTION_SCAN**

Find:

```gdscript
enum State {
	NONE,
	COMBAT_START,
	TURN_START,
	ACTION_SELECT,
	ACTION_EXECUTION,
	REACTION_SCAN,
	TURN_END,
	COMBAT_END
}
```

Replace with:

```gdscript
enum State {
	NONE,
	COMBAT_START,
	TURN_START,
	ACTION_SELECT,
	ACTION_EXECUTION,
	TURN_END,
	COMBAT_END
}
```

- [ ] **Step 2: Update _transition() — remove REACTION_SCAN case**

Find:

```gdscript
func _transition(next: State) -> void:
	var msg: String = State.keys()[_state] + " -> " + State.keys()[next]
	Log.info("CombatFSM", msg)
	_state = next
	match next:
		State.COMBAT_START:     _enter_combat_start()
		State.TURN_START:       _enter_turn_start()
		State.ACTION_SELECT:    _enter_action_select()
		State.ACTION_EXECUTION: _enter_action_execution()
		State.REACTION_SCAN:    _enter_reaction_scan()
		State.TURN_END:         _enter_turn_end()
		State.COMBAT_END:       _enter_combat_end()
```

Replace with:

```gdscript
func _transition(next: State) -> void:
	var msg: String = State.keys()[_state] + " -> " + State.keys()[next]
	Log.info("CombatFSM", msg)
	_state = next
	match next:
		State.COMBAT_START:     _enter_combat_start()
		State.TURN_START:       _enter_turn_start()
		State.ACTION_SELECT:    _enter_action_select()
		State.ACTION_EXECUTION: _enter_action_execution()
		State.TURN_END:         _enter_turn_end()
		State.COMBAT_END:       _enter_combat_end()
```

- [ ] **Step 3: Replace _enter_action_execution()**

Find the entire `_enter_action_execution` method:

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

	CombatEvents.action_announced.emit(_pending_mnemonic.mnemonic_name)
	await get_tree().create_timer(0.5).timeout

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

Replace with:

```gdscript
func _enter_action_execution() -> void:
	if _pending_mnemonic == null:
		Log.warn("ActionExecution — no mnemonic, skipping")
		_transition(State.TURN_END)
		return

	_action_pipeline.run(_pending_mnemonic, _active_actor, _pending_target, _actors)
	await _action_pipeline.pipeline_complete
	_transition(State.TURN_END)
```

- [ ] **Step 4: Delete _enter_reaction_scan()**

Find and delete this entire method:

```gdscript
func _enter_reaction_scan() -> void:
	# STUB: reactions not yet implemented
	if _check_combat_end():
		return
	_transition(State.TURN_END)
```

- [ ] **Step 5: Verify the full file looks correct**

`CombatFSM.gd` should have no reference to `REACTION_SCAN` or `_enter_reaction_scan`. Use `get_errors` or `validate_script` via Godot MCP to confirm no syntax errors.

- [ ] **Step 6: Run scene and test a full combat round**

Run the combat scene. Perform these checks manually:

1. A player character uses a skill on an enemy — the action banner appears, damage resolves, numbers show correctly.
2. An enemy takes lethal damage — combat ends with a win (Godot console shows `CombatEnd — player_won: true`).
3. Console log shows `ACTION_EXECUTION -> TURN_END` (not `ACTION_EXECUTION -> REACTION_SCAN -> TURN_END`).
4. Console shows `ActionPipeline — resolved` with attacker, target, and total damage.
5. No new errors or warnings beyond pre-existing ones.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/CombatFSM.gd
git commit -m "refactor: delegate action execution to ActionPipeline, remove REACTION_SCAN and AP/MP guards from CombatFSM"
```

---

## Self-Review Checklist

- **ActionPipeline node owns execution** → Task 3 + Task 4 ✓
- **Direct iteration replaces signal broadcast** → Task 3 (collect_triggers loop) ✓
- **check_trigger stub on RuntimeToken** → Task 1 ✓
- **collect_triggers on ActiveTokens** → Task 1 ✓
- **ActionContext queues hold RuntimeTokens, trigger_context bridges reactions** → Task 2 ✓
- **ActionContext negated/cancelled flags for nullification and status-lock** → Task 2 ✓
- **FSM becomes pure state pump** → Task 6 ✓
- **REACTION_SCAN state removed** → Task 6, Steps 1–4 ✓
- **AP/MP guards moved from FSM to ActionPipeline validation** → Task 3 + Task 6 ✓
- **_check_combat_end consolidated to TURN_END** → removed from action_execution and reaction_scan in Task 6 ✓
- **Downed check owned by ActionPipeline** → Task 3 ✓
- **action_resolved moved to ActionPipeline** → Task 3 ✓
- **HP cost moved to ActionPipeline** → Task 3 ✓
- **actors passed through to pipeline** → Tasks 5 and 6 ✓
- **CombatScene ai_behavior loop removed** → Task 5 ✓
- **Reaction tokens (COUNTER, HAMEDO, VIGIL)** → Out of scope, infrastructure wired only ✓
- **Connect/disconnect lifecycle** → Out of scope, not needed with direct iteration ✓
- **action_resolved carries full context** → Signal updated to `action_resolved(context: ActionContext)` in CombatEvents + both emit calls in ActionPipeline updated → Task 3 ✓
- **FSM never hangs on bad input** → Null guard at top of run() fires pipeline_complete before any await → Task 3 ✓
- **COVER/INTERCEPT classified as passive token (not reaction)** → Design notes written (redirect universal, AoE dedup, eager downed cleanup, pair consumption) ✓
