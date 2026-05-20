# Action Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bloated `_enter_action_execution` FSM handler with a dedicated `ActionPipeline` node that owns the full action resolution cycle — announce, pre-execution reactions, primary execution, post-execution reactions — while trimming CombatFSM to a pure state pump.

**Architecture:** `ActionPipeline` is a sibling Node under `CombatScene`. `CombatFSM` calls `pipeline.run()` and awaits `pipeline_complete`. `CombatEvents` broadcasts two new synchronous signals (`action_pre_execution`, `action_post_execution`) that armed tokens will eventually self-select against. `ActionContext` gains two queue arrays that tokens write into during broadcasts. Today those queues are always empty — the mechanism is wired, reaction tokens are future work.

**Tech Stack:** GDScript, Godot 4.6, Godot MCP tools for scene manipulation.

---

## File Map

| Action | Path |
|---|---|
| **Create** | `scripts/combat/ActionPipeline.gd` |
| **Create** | `scenes/combat/components/action_pipeline.tscn` |
| **Modify** | `scripts/combat/CombatEvents.gd` |
| **Modify** | `scripts/combat/ActionContext.gd` |
| **Modify** | `scripts/combat/CombatFSM.gd` |
| **Modify** | `scripts/combat/CombatScene.gd` |
| **Modify** | `scenes/combat/combat_scene.tscn` (via Godot MCP) |

---

## Task 1: Add broadcast signals to CombatEvents

**Files:**
- Modify: `scripts/combat/CombatEvents.gd`

- [ ] **Step 1: Add two new signals after the existing `action_announced` line**

Open `scripts/combat/CombatEvents.gd`. The file currently ends with:

```gdscript
signal dot_ticked(token: RuntimeToken, context: ActionContext)
signal action_announced(text: String)
```

Replace those two lines with:

```gdscript
signal dot_ticked(token: RuntimeToken, context: ActionContext)
signal action_announced(text: String)

# Synchronous-only. Do NOT await inside any connected handler.
# ActionPipeline emits these and immediately reads the queues that listeners populate.
# An await inside a handler will break queue ordering silently.
signal action_pre_execution(context: ActionContext)
signal action_post_execution(context: ActionContext)
```

- [ ] **Step 2: Verify the scene runs clean**

Use the Godot MCP tool `get_errors` or run the scene (F5 in editor). Expected: zero new errors in the console.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/CombatEvents.gd
git commit -m "feat: add action_pre_execution and action_post_execution signals to CombatEvents"
```

---

## Task 2: Extend ActionContext with execution queues

**Files:**
- Modify: `scripts/combat/ActionContext.gd`

- [ ] **Step 1: Add queue fields to ActionContext**

Open `scripts/combat/ActionContext.gd`. The file currently reads:

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

Replace the whole file with:

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

# Populated during action_pre_execution broadcast.
# Each entry is an ActionContext for a reaction that fires before the primary action.
var pre_queue: Array = []

# Populated during action_post_execution broadcast.
# Each entry is an ActionContext for a reaction that fires after the primary action.
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
git commit -m "feat: add pre_queue and post_queue to ActionContext for reaction pipeline"
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

func run(mnemonic: MnemonicRes, attacker: CombatCharacter, target: CombatCharacter) -> void:
	var context := ActionContext.new()
	context.mnemonic = mnemonic
	context.attacker = attacker
	context.primary_target = target

	# Announce and hold for presentation
	CombatEvents.action_announced.emit(mnemonic.mnemonic_name)
	await get_tree().create_timer(0.5).timeout

	# PRE-PASS — broadcast to armed tokens. Synchronous: pre_queue is fully populated
	# before the next line. Reaction tokens that fire before the primary append here.
	CombatEvents.action_pre_execution.emit(context)
	for reaction_ctx: ActionContext in context.pre_queue:
		SkillExecutor.execute(reaction_ctx)

	# Primary action
	SkillExecutor.execute(context)

	# HP blood cost — paid after execution, not before (it's a price, not a prerequisite)
	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)

	# Downed detection for primary target
	if context.primary_target.vitals.is_downed():
		Log.info("ActionPipeline — downed", context.primary_target.character_name)
		CombatEvents.actor_downed.emit(context.primary_target)

	# POST-PASS — broadcast with updated context. Synchronous: post_queue is fully populated
	# before the next line. Reaction tokens that fire after the primary append here.
	CombatEvents.action_post_execution.emit(context)
	for reaction_ctx: ActionContext in context.post_queue:
		SkillExecutor.execute(reaction_ctx)
		if reaction_ctx.primary_target.vitals.is_downed():
			Log.info("ActionPipeline — downed (reaction)", reaction_ctx.primary_target.character_name)
			CombatEvents.actor_downed.emit(reaction_ctx.primary_target)

	Log.info("ActionPipeline — resolved", "%s->%s total:%d" % [
		attacker.character_name, context.primary_target.character_name, context.total_damage])
	CombatEvents.action_resolved.emit(attacker)
	pipeline_complete.emit()
```

- [ ] **Step 2: Verify the scene runs clean**

Run the scene or use `get_errors`. Expected: zero new errors (pipeline not wired yet, just authored).

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ActionPipeline.gd
git commit -m "feat: implement ActionPipeline node — full action resolution with pre/post reaction slots"
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

- [ ] **Step 1: Add ActionPipeline reference and pass it to the FSM in CombatScene.gd**

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

- [ ] **Step 2: Update CombatFSM.start() to accept ActionPipeline**

Open `scripts/combat/CombatFSM.gd`. Add a `_action_pipeline` variable declaration after the existing `var` block, and update `start()` to accept and store it.

Find these lines near the top of the file:

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

Run the scene or use `get_errors`. Expected: zero new errors. Combat should still work identically to before — the pipeline is wired but not yet called.

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/CombatScene.gd scripts/combat/CombatFSM.gd
git commit -m "feat: wire ActionPipeline reference through CombatScene into CombatFSM"
```

---

## Task 6: Trim CombatFSM — delegate execution, remove REACTION_SCAN

**Files:**
- Modify: `scripts/combat/CombatFSM.gd`

This is the final surgical step. Three things happen together: `_enter_action_execution` is replaced, `REACTION_SCAN` is deleted, and `_check_combat_end` is consolidated to `TURN_END` only.

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

Find the entire `_enter_action_execution` method (lines 74–117 in the original file):

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

	if _active_actor.vitals.cur_ap < _pending_mnemonic.ap_cost \
			or _active_actor.vitals.cur_mp < _pending_mnemonic.mp_cost:
		Log.warn("ActionExecution — insufficient AP/MP, skipping")
		_transition(State.TURN_END)
		return

	_active_actor.vitals.spend_ap(_pending_mnemonic.ap_cost)
	_active_actor.vitals.spend_mp(_pending_mnemonic.mp_cost)

	_action_pipeline.run(_pending_mnemonic, _active_actor, _pending_target)
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

After edits, `CombatFSM.gd` should have no reference to `REACTION_SCAN` or `_enter_reaction_scan`. Use `get_errors` or `validate_script` via Godot MCP to confirm no syntax errors.

- [ ] **Step 6: Run scene and test a full combat round**

Run the combat scene. Perform these checks manually:

1. A player character uses a skill on an enemy — the action banner appears, damage resolves, numbers show correctly.
2. An enemy takes lethal damage — the combat ends with a win (check Godot console for `CombatEnd — player_won: true`).
3. Confirm the console log shows the new flow: `ACTION_EXECUTION -> TURN_END` (not `ACTION_EXECUTION -> REACTION_SCAN -> TURN_END`).
4. Confirm `ActionPipeline — resolved` appears in the log with attacker, target, and total damage.
5. No errors or warnings in the Godot console beyond pre-existing ones.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/CombatFSM.gd
git commit -m "refactor: delegate action execution to ActionPipeline, remove REACTION_SCAN state from CombatFSM"
```

---

## Self-Review Checklist

- **Spec: ActionPipeline node as execution owner** → Task 3 + Task 4 ✓
- **Spec: CombatEvents broadcast signals** → Task 1 ✓
- **Spec: ActionContext queues** → Task 2 ✓
- **Spec: FSM becomes pure state pump** → Task 6 ✓
- **Spec: REACTION_SCAN state removed** → Task 6, Steps 1–4 ✓
- **Spec: _check_combat_end consolidated to TURN_END** → TURN_END already has it; removed from action_execution and reaction_scan in Task 6 ✓
- **Spec: Downed check owned by ActionPipeline** → Task 3, Step 1 ✓
- **Spec: action_resolved moved to ActionPipeline** → Task 3, Step 1 ✓
- **Spec: HP cost moved to ActionPipeline** → Task 3, Step 1 ✓
- **Spec: Synchronous constraint documented on signals** → Task 1, Step 1 ✓
- **Reaction tokens (COUNTER, HAMEDO, VIGIL)** → Out of scope, infrastructure wired only ✓
