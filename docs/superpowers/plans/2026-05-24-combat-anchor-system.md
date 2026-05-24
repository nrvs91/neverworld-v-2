# Combat Anchor System + Approach/Recover Motion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CombatAnchors autoload holding three named party-level anchor positions, then wire CombatVisuals approach/recover tween motion into ActionPipeline for melee skills.

**Architecture:** Three Marker3D nodes already placed in combat_scene.tscn are registered with a lightweight CombatAnchors autoload at combat start. CombatVisuals gains async approach()/recover() methods that tween its own position. ActionPipeline calls those two methods around SkillExecutor.execute(), gated by mnemonic.is_melee. All tween logic stays inside CombatVisuals.

**Tech Stack:** GDScript, Godot 4.6, Tween node, MCP Godot tooling for autoload registration.

**Spec:** `docs/superpowers/specs/2026-05-24-combat-anchor-system-design.md`

---

## File Map

| File | Action |
|------|--------|
| `scripts/combat/CombatAnchors.gd` | Create — autoload script, holds three anchor refs |
| `scenes/combat/combat_anchors.tscn` | Create — autoload scene wrapping the script |
| `project.godot` | Modify — register CombatAnchors autoload via MCP |
| `scripts/combat/CombatScene.gd` | Modify — register anchors on init, clear on exit |
| `CombatVisuals.gd` | Modify — implement approach() and recover() |
| `scripts/combat/ActionPipeline.gd` | Modify — call approach/recover around skill execution |

---

## Task 1: CombatAnchors Script and Scene

**Files:**
- Create: `scripts/combat/CombatAnchors.gd`
- Create: `scenes/combat/combat_anchors.tscn`
- Modify: `project.godot` (via MCP)

- [ ] **Step 1: Create the script**

Create `scripts/combat/CombatAnchors.gd`:

```gdscript
class_name CombatAnchors
extends Node

var player_party: Node3D
var enemy_party: Node3D
var middle: Node3D

func register(p: Node3D, e: Node3D, m: Node3D) -> void:
	player_party = p
	enemy_party = e
	middle = m
	Log.info("CombatAnchors — registered")

func clear() -> void:
	player_party = null
	enemy_party = null
	middle = null
	Log.info("CombatAnchors — cleared")
```

- [ ] **Step 2: Create the autoload scene**

Create `scenes/combat/combat_anchors.tscn` with this exact content:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/combat/CombatAnchors.gd" id="1_anchors"]

[node name="CombatAnchors" type="Node"]
script = ExtResource("1_anchors")
```

- [ ] **Step 3: Register the autoload via MCP**

Use the MCP `setup_autoload` tool:
- name: `CombatAnchors`
- path: `res://scenes/combat/combat_anchors.tscn`

- [ ] **Step 4: Verify in Godot**

Open Project → Project Settings → Autoloads. Confirm `CombatAnchors` appears in the list alongside `CombatEvents`, `PartyManager`, etc.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/CombatAnchors.gd scenes/combat/combat_anchors.tscn project.godot
git commit -m "feat: add CombatAnchors autoload"
```

---

## Task 2: CombatScene Registration

**Files:**
- Modify: `scripts/combat/CombatScene.gd`

The three Marker3D anchor nodes already exist in `combat_scene.tscn` under the path:
- `Anchors/PlayerPartyAnchor`
- `Anchors/EnemyPartyAnchor`
- `Anchors/MiddleAnchor`

- [ ] **Step 1: Add @onready refs and registration to CombatScene.gd**

Replace the current `CombatScene.gd` contents with:

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
@onready var _player_party_anchor: Marker3D = $Anchors/PlayerPartyAnchor
@onready var _enemy_party_anchor: Marker3D = $Anchors/EnemyPartyAnchor
@onready var _middle_anchor: Marker3D = $Anchors/MiddleAnchor

func _exit_tree() -> void:
	CombatAnchors.clear()

func _clear_environment() -> void:
	for child in environment_mount.get_children():
		child.queue_free()

func initialize(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	combat_camera.make_current()
	_clear_environment()
	player_spawner.initialize()
	enemy_spawner.initialize(composition)
	CombatAnchors.register(_player_party_anchor, _enemy_party_anchor, _middle_anchor)
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

- [ ] **Step 2: Run the combat scene and check the log**

Run `godot --path /home/bart/neverworld-v-2` and start a combat encounter. Check the Godot console output for:
```
CombatAnchors — registered
```
This confirms registration is firing. No errors expected.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/CombatScene.gd
git commit -m "feat: register combat anchors at combat start"
```

---

## Task 3: CombatVisuals — approach() and recover()

**Files:**
- Modify: `CombatVisuals.gd`

`CombatVisuals` is a `Node3D` child of `CombatCharacter`. Its `position` is in `CombatCharacter`'s local space — normally `Vector3.ZERO`. Since `CombatCharacter` has no rotation (slot transforms are translation-only), local-space direction equals world-space direction. The tween moves `self.position` by the world-space delta scaled to 70%, which correctly slides the visual toward the target.

- [ ] **Step 1: Implement approach() and recover() in CombatVisuals.gd**

Replace the current `CombatVisuals.gd` contents with:

```gdscript
class_name CombatVisuals
extends Node3D

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

var _base_state: StringName = &"Idle"
var _action_playing: bool = false
var _home: Vector3

func setup(sprite_frames: SpriteFrames) -> void:
	sprite.sprite_frames = sprite_frames
	if sprite_frames.has_animation(_base_state):
		sprite.play(_base_state)
	else:
		var fallback := sprite_frames.get_animation_names()[0]
		sprite.play(fallback)
		Log.warn("CombatVisuals: no Idle animation, playing", fallback)
	Log.info("CombatVisuals setup")

func set_base_state(state: StringName) -> void:
	_base_state = state
	if not _action_playing:
		sprite.play(_base_state)
	Log.debug("CombatVisuals base state set:", state)

func approach(target_global_pos: Vector3, duration: float = 0.2) -> void:
	_home = position
	_action_playing = true
	var delta := target_global_pos - global_position
	var destination := _home + delta * 0.7
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", destination, duration)
	await tween.finished
	Log.debug("CombatVisuals — approached")

func recover(duration: float = 0.2) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", _home, duration)
	await tween.finished
	_action_playing = false
	Log.debug("CombatVisuals — recovered")

# Animation signal hooks — called by AnimatedSprite3D frame signals when art exists
func attack_to_motion_hold() -> void: pass
func attack_to_strike_hold() -> void: pass
func attack_to_recover_hold() -> void: pass
func attack_finish() -> void: pass

func cast_to_motion_hold() -> void: pass
func cast_to_release_hold() -> void: pass
func cast_to_recover_hold() -> void: pass
func cast_finish() -> void: pass

func play_combat_entry() -> void: pass
func play_combat_exit() -> void: pass
func play_item_use() -> void: pass
func play_hurt() -> void: pass
func play_dodge_slide() -> void: pass
func play_ko() -> void: pass
func play_custom(anim_name: String) -> void: pass
```

- [ ] **Step 2: Commit**

```bash
git add CombatVisuals.gd
git commit -m "feat: implement approach/recover tween in CombatVisuals"
```

---

## Task 4: ActionPipeline — Wire Motion Calls

**Files:**
- Modify: `scripts/combat/ActionPipeline.gd`

Approach fires after `_can_execute()` passes and resources are spent — motion only happens if the action will actually execute. Recover fires immediately after `SkillExecutor.execute()`, before the 0.4s damage number pause.

- [ ] **Step 1: Add approach/recover calls to ActionPipeline.gd**

In `ActionPipeline.gd`, replace the block between resource spending and `SkillExecutor.execute()`:

Current (lines 50–58):
```gdscript
	# Spend resources — only after validation confirms the action will resolve
	attacker.vitals.spend_ap(mnemonic.ap_cost)
	attacker.vitals.spend_mp(mnemonic.mp_cost)

	# Primary action
	SkillExecutor.execute(context)

	# HP blood cost — paid after execution, not before (it's a price, not a prerequisite)
	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)
```

Replace with:
```gdscript
	# Spend resources — only after validation confirms the action will resolve
	attacker.vitals.spend_ap(mnemonic.ap_cost)
	attacker.vitals.spend_mp(mnemonic.mp_cost)

	if mnemonic.is_melee:
		await attacker.visuals.approach(target.get_parent().global_position)

	# Primary action
	SkillExecutor.execute(context)

	if mnemonic.is_melee:
		await attacker.visuals.recover()

	# HP blood cost — paid after execution, not before (it's a price, not a prerequisite)
	if mnemonic.hp_cost_percent > 0.0:
		attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)
```

- [ ] **Step 2: Run the combat scene and test a melee attack**

Run `godot --path /home/bart/neverworld-v-2`. Enter combat and trigger a melee mnemonic. Expected:
- Attacker sprite slides toward the target (≈70% of the distance, 0.2s, SINE/EASE_OUT)
- Hit resolves
- Attacker sprite slides back (0.2s, SINE/EASE_IN)
- Damage numbers and post-reactions proceed normally

Also trigger a non-melee mnemonic if one exists. Expected: no motion, behaviour identical to before.

Check Godot console for:
```
CombatVisuals — approached
CombatVisuals — recovered
```

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ActionPipeline.gd
git commit -m "feat: wire approach/recover motion into ActionPipeline for melee skills"
```

---

## Done

All four tasks complete. The anchor system is live (`CombatAnchors.player_party`, `.enemy_party`, `.middle` available globally) and melee attacks now physically move the attacker sprite toward the target and back. Non-melee skills are unaffected. Future extension: when cast/ranged motion is needed, `MnemonicResource.is_melee: bool` becomes a `VisualType` enum and the ActionPipeline gate expands to a match block.
