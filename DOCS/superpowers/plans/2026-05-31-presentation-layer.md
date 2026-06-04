# Presentation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full combat presentation pipeline — per-character sprite components, an action dispatch node, and one authored skill animation scene as proof of concept.

**Architecture:** `CharacterVisualComponent` lives on every `CombatCharacter` and owns the sprite, base state, and animation interface. `ActionAnimator` sits in `CombatScene`, subscribes to `action_executed`, and instantiates the right animation scene by convention. `ActionPipeline` awaits `action_animation_complete` before continuing to post-reactions, making the pipeline fully sequential.

**Tech Stack:** Godot 4.6, GDScript, `AnimatedSprite3D`, `CPUParticles3D`, `AnimationPlayer` (SFX only), `Tween`

**Spec:** `DOCS/presentation_layer_spec.md`

---

## File Map

**Create:**
- `scripts/combat/CharacterVisualComponent.gd`
- `scenes/combat/components/character_visual_component.tscn`
- `scripts/combat/ActionAnimator.gd`
- `scenes/combat/components/action_animator.tscn`
- `resources/mnemonics/uskrav/uskrav_anim.tscn` (script embedded, no separate .gd)

**Modify:**
- `scripts/combat/CombatEvents.gd` — add `mnemonic` param to `action_executed`
- `scripts/combat/ActionPipeline.gd` — update emit + replace 0.4s timer with `await action_animation_complete`
- `scripts/combat/tokens/RuntimeToken_Damage.gd` — update emit
- `scripts/combat/tokens/RuntimeToken_Counter.gd` — update emit
- `scripts/combat/CombatCharacter.gd` — add `var visual: CharacterVisualComponent`
- `scenes/combat/combat_character.tscn` — add `CharacterVisualComponent` child
- `scenes/combat/combat_scene.tscn` — add `ActionAnimator` node

**Restructure:**
- `resources/mnemonics/*.tres` → each into its own subfolder

---

## Task 1: CharacterVisualComponent

**Files:**
- Create: `scripts/combat/CharacterVisualComponent.gd`
- Create: `scenes/combat/components/character_visual_component.tscn`
- Modify: `scripts/combat/CombatCharacter.gd`
- Modify: `scenes/combat/combat_character.tscn`

- [ ] **Step 1: Create the script**

Create `scripts/combat/CharacterVisualComponent.gd`:

```gdscript
class_name CharacterVisualComponent
extends Node3D

enum Base { IDLE, LOW_HP, KO }

const LOW_HP_THRESHOLD := 0.25

var home_position: Vector3
var sprite: AnimatedSprite3D
var _base: Base = Base.IDLE
var _vitals: VitalsComponent

func setup(vitals: VitalsComponent) -> void:
	_vitals = vitals
	_vitals.vitals_changed.connect(_on_vitals_changed)

func _ready() -> void:
	home_position = global_position
	sprite = $AnimatedSprite3D

func play(anim: String) -> void:
	if sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		Log.warn("CharacterVisualComponent — missing animation", anim)
		return
	sprite.play(anim)

func play_and_wait(anim: String) -> void:
	play(anim)
	if sprite.is_playing():
		await sprite.animation_finished

func play_hurt() -> void:
	play("hurt")
	if sprite.is_playing():
		await sprite.animation_finished
	_restore_base()

func set_base(state: Base) -> void:
	_base = state
	_restore_base()

func _restore_base() -> void:
	match _base:
		Base.IDLE:   play("idle")
		Base.LOW_HP: play("idle_low_hp")
		Base.KO:     play("ko")

func _on_vitals_changed() -> void:
	if _vitals.is_downed():
		set_base(Base.KO)
	elif _vitals.cur_hp < _vitals.max_hp * LOW_HP_THRESHOLD:
		set_base(Base.LOW_HP)
	else:
		set_base(Base.IDLE)
```

- [ ] **Step 2: Create the scene**

Create `scenes/combat/components/character_visual_component.tscn` with this structure:

```
CharacterVisualComponent (Node3D, script = CharacterVisualComponent.gd)
└── AnimatedSprite3D
```

`AnimatedSprite3D` has no SpriteFrames assigned by default — each character sets their own.

- [ ] **Step 3: Add `visual` reference to CombatCharacter**

In `scripts/combat/CombatCharacter.gd`, add:

```gdscript
@onready var visual: CharacterVisualComponent = $CharacterVisualComponent
```

Also call `visual.setup(vitals)` wherever the character is initialised after spawning. Check `CombatCharacter.gd` for the existing `setup()` or `_ready()` method and add:

```gdscript
visual.setup(vitals)
```

- [ ] **Step 4: Add CharacterVisualComponent to combat_character.tscn**

In `scenes/combat/combat_character.tscn`, instance `character_visual_component.tscn` as a child of `CombatCharacter`. The scene tree becomes:

```
CombatCharacter (Node3D)
├── VitalsComponent
├── StatsComponent
├── ActiveTokens
└── CharacterVisualComponent
    └── AnimatedSprite3D
```

- [ ] **Step 5: Verify — run the scene**

Run the main scene. Open the Godot remote scene tree during play. Confirm each spawned `CombatCharacter` has a `CharacterVisualComponent` child with an `AnimatedSprite3D` underneath. No errors in the log.

- [ ] **Step 6: Commit**

```bash
git add scripts/combat/CharacterVisualComponent.gd \
        scenes/combat/components/character_visual_component.tscn \
        scripts/combat/CombatCharacter.gd \
        scenes/combat/combat_character.tscn
git commit -m "feat: add CharacterVisualComponent to CombatCharacter"
```

---

## Task 2: Mnemonic folder restructure

**Files:**
- Move: all `.tres` files under `resources/mnemonics/` into per-skill subfolders

Each mnemonic's `mnemonic_name` (lowercased) is its folder name. Check the value inside each `.tres` file before moving.

Known mappings (verify each by opening the `.tres` and reading `mnemonic_name`):

| File | mnemonic_name | Target folder |
|------|--------------|---------------|
| `uskrav_tergo_lupi.tres` | "Uskrav" | `uskrav/` |
| `viper_strike.tres` | check | `viper_strike/` |
| `counter_stance.tres` | check | `counter_stance/` |
| `empower_stance.tres` | check | `empower_stance/` |
| `enemy_basic_strike.tres` | check | `enemy_basic_strike/` |
| `envenom.tres` | check | `envenom/` |
| `stun_strike.tres` | check | `stun_strike/` |
| `vigil_stance.tres` | check | `vigil_stance/` |
| `weaken_strike.tres` | check | `weaken_strike/` |

`targeting_self.tres` and `targeting_single_enemy.tres` are targeting helpers, not mnemonics — leave them in place.

- [ ] **Step 1: Create subfolders and move files**

For each mnemonic, create its subfolder and move the `.tres`:

```bash
cd /home/bart/Projects/neverworld-v-2/resources/mnemonics
mkdir uskrav && mv uskrav_tergo_lupi.tres uskrav/
mkdir viper_strike && mv viper_strike.tres viper_strike/
mkdir counter_stance && mv counter_stance.tres counter_stance/
mkdir empower_stance && mv empower_stance.tres empower_stance/
mkdir enemy_basic_strike && mv enemy_basic_strike.tres enemy_basic_strike/
mkdir envenom && mv envenom.tres envenom/
mkdir stun_strike && mv stun_strike.tres stun_strike/
mkdir vigil_stance && mv vigil_stance.tres vigil_stance/
mkdir weaken_strike && mv weaken_strike.tres weaken_strike/
```

- [ ] **Step 2: Rescan filesystem in Godot**

Open Godot editor. In the FileSystem dock, right-click and select "Rescan Filesystem" (or use the MCP tool `rescan_filesystem`). Godot will update all resource UIDs automatically.

- [ ] **Step 3: Verify no broken references**

Run the scene. If any resource paths are broken, Godot will report errors loading `.tres` files. Fix by updating the path in any `.tres` or `.tscn` that referenced the old location.

Check character resources that assign mnemonics:

```bash
grep -r "mnemonics/" /home/bart/Projects/neverworld-v-2/resources/characters/
```

Update any paths found.

- [ ] **Step 4: Commit**

```bash
git add resources/mnemonics/
git commit -m "refactor: move mnemonic .tres files into per-skill subfolders"
```

---

## Task 3: ActionAnimator + action_executed signal fix

**Files:**
- Modify: `scripts/combat/CombatEvents.gd`
- Modify: `scripts/combat/ActionPipeline.gd`
- Modify: `scripts/combat/tokens/RuntimeToken_Damage.gd`
- Modify: `scripts/combat/tokens/RuntimeToken_Counter.gd`
- Create: `scripts/combat/ActionAnimator.gd`
- Create: `scenes/combat/components/action_animator.tscn`
- Modify: `scenes/combat/combat_scene.tscn`

**Signal fix rationale:** `ActionAnimator` needs `mnemonic_name` to resolve the animation scene path. Adding `mnemonic: MnemonicResource` to `action_executed` is the minimal change. Token-fired emissions (from `RuntimeToken_Damage`, `RuntimeToken_Counter`) pass `null` — ActionAnimator's fallback handles it.

- [ ] **Step 1: Update action_executed signal signature**

In `scripts/combat/CombatEvents.gd`, change:

```gdscript
signal action_executed(actor: CombatCharacter, targets: Array[CombatCharacter], damage: int)
```

To:

```gdscript
signal action_executed(actor: CombatCharacter, targets: Array[CombatCharacter], damage: int, mnemonic: MnemonicResource)
```

- [ ] **Step 2: Update all emit sites**

In `scripts/combat/ActionPipeline.gd`, change:

```gdscript
CombatEvents.action_executed.emit(context.source, context.targets, context.total_damage)
```

To:

```gdscript
CombatEvents.action_executed.emit(context.source, context.targets, context.total_damage, context.mnemonic)
```

In `scripts/combat/tokens/RuntimeToken_Damage.gd`, change:

```gdscript
CombatEvents.action_executed.emit(source, [owner], result.damage)
```

To:

```gdscript
CombatEvents.action_executed.emit(source, [owner], result.damage, null)
```

In `scripts/combat/tokens/RuntimeToken_Counter.gd`, change:

```gdscript
CombatEvents.action_executed.emit(owner, [attacker], result.damage)
```

To:

```gdscript
CombatEvents.action_executed.emit(owner, [attacker], result.damage, null)
```

- [ ] **Step 3: Update any subscribers of action_executed**

Search for all connections to `action_executed`:

```bash
grep -rn "action_executed" /home/bart/Projects/neverworld-v-2/scripts/
grep -rn "action_executed" /home/bart/Projects/neverworld-v-2/scenes/
```

For each subscriber, add the new `mnemonic` parameter to the callback signature. GDScript won't crash on extra signal params for untyped callbacks, but **typed callbacks will fail** — any function with explicit type hints must include the new param. Use `_mnemonic` to ignore it:

```gdscript
func _on_action_executed(actor: CombatCharacter, targets: Array[CombatCharacter], damage: int, _mnemonic: MnemonicResource) -> void:
```

Check UI scripts (under `scripts/combat/ui/`) especially — `DamageNumber.gd` is a known subscriber.

- [ ] **Step 4: Create ActionAnimator script**

Create `scripts/combat/ActionAnimator.gd`:

```gdscript
class_name ActionAnimator
extends Node

func _ready() -> void:
	CombatEvents.action_executed.connect(_on_action_executed)

func _exit_tree() -> void:
	CombatEvents.action_executed.disconnect(_on_action_executed)

func _on_action_executed(source: CombatCharacter, targets: Array[CombatCharacter], _damage: int, mnemonic: MnemonicResource) -> void:
	if mnemonic == null:
		CombatEvents.action_animation_complete.emit()
		return

	var id := mnemonic.mnemonic_name.to_lower()
	var path := "res://resources/mnemonics/%s/%s_anim.tscn" % [id, id]

	if not ResourceLoader.exists(path):
		Log.warn("ActionAnimator — no animation scene for", id)
		CombatEvents.action_animation_complete.emit()
		return

	Log.info("ActionAnimator — playing", id)
	var scene := load(path).instantiate()
	add_child(scene)
	await scene.execute(source, targets)
	CombatEvents.action_animation_complete.emit()
```

- [ ] **Step 5: Create ActionAnimator scene**

Create `scenes/combat/components/action_animator.tscn`:

```
ActionAnimator (Node, script = ActionAnimator.gd)
```

No children needed — animation scenes are added dynamically.

- [ ] **Step 6: Add ActionAnimator to CombatScene**

In `scenes/combat/combat_scene.tscn`, instance `action_animator.tscn` as a child of `CombatScene`, alongside `ActionPipeline` and `CombatFSM`.

- [ ] **Step 7: Verify — run the scene**

Run the main scene and trigger a combat action. The log should show:

```
ActionAnimator — no animation scene for uskrav
```

(or whichever skill fired). No crash, no hang. The fallback fires `action_animation_complete` and combat continues.

- [ ] **Step 8: Commit**

```bash
git add scripts/combat/CombatEvents.gd \
        scripts/combat/ActionPipeline.gd \
        scripts/combat/tokens/RuntimeToken_Damage.gd \
        scripts/combat/tokens/RuntimeToken_Counter.gd \
        scripts/combat/ActionAnimator.gd \
        scenes/combat/components/action_animator.tscn \
        scenes/combat/combat_scene.tscn
git commit -m "feat: add ActionAnimator, fix action_executed signal to carry mnemonic"
```

---

## Task 4: ActionPipeline — replace timer with animation await

**Files:**
- Modify: `scripts/combat/ActionPipeline.gd`

- [ ] **Step 1: Replace the post-execution timer**

In `scripts/combat/ActionPipeline.gd`, the current code after `SkillExecutor.execute()` has a `create_timer(0.4)` placeholder. Replace it:

Find:
```gdscript
SkillExecutor.execute(context)
CombatEvents.action_executed.emit(context.source, context.targets, context.total_damage, context.mnemonic)

if mnemonic.hp_cost_percent > 0.0:
    attacker.vitals.spend_hp_percent(mnemonic.hp_cost_percent)
```

The 0.4s timer should be just after `action_executed` — find it and replace with:

```gdscript
await CombatEvents.action_animation_complete
```

Also remove the `await get_tree().create_timer(0.8).timeout` in `CombatFSM._enter_turn_end()` if it exists as another presentation placeholder — check the comment on that line. If it says "replace with animation_finished", remove it. If it's doing something else, leave it.

- [ ] **Step 2: Verify — run the scene**

Run the scene and trigger combat. With no animation scenes present yet, the pipeline should:
1. Log the `ActionAnimator` warning
2. Immediately emit `action_animation_complete`
3. Continue to post-reactions and turn end

Combat should complete turns at the same pace as before. No hangs.

- [ ] **Step 3: Commit**

```bash
git add scripts/combat/ActionPipeline.gd
git commit -m "feat: ActionPipeline awaits action_animation_complete instead of hardcoded timer"
```

---

## Task 5: Uskrav animation scene (proof of concept)

**Files:**
- Create: `resources/mnemonics/uskrav/uskrav_anim.tscn` (script embedded directly on root node)

This task proves the full pipeline end-to-end. Uskrav is a melee skill — wind up, dash to target, attack, hit VFX, recover.

**Prerequisite:** The character `SpriteFrames` resources must have animations named `wind_up`, `dash`, `attack`, `recover`, `hurt`, and `idle`. If these don't exist yet in the existing `SpriteFrames` resources, add placeholder single-frame animations with those names before continuing.

- [ ] **Step 1: Verify or create animation names in SpriteFrames**

Open `resources/characters/player/SkuggeAnimations.tres` in the Godot editor. In the SpriteFrames editor, confirm these animations exist (or create them as single-frame placeholders using any frame from the sprite sheet):

- `idle`
- `wind_up`
- `dash`
- `attack`
- `recover`
- `hurt`

Repeat for `VargiAnimations.tres` and any enemy SpriteFrames. All characters who can use a mnemonic need the same animation names.

- [ ] **Step 2: Attach the script to the scene root**

In Godot, create `resources/mnemonics/uskrav/uskrav_anim.tscn` with a `Node3D` as root, then attach a new script directly to that root node (saved inline, not as a separate file). The script:

```gdscript
extends Node3D

@onready var hit_vfx: CPUParticles3D = $HitVFX
@onready var sfx_player: AnimationPlayer = $SFXPlayer

func execute(source: CombatCharacter, targets: Array[CombatCharacter]) -> void:
	await source.visual.play_and_wait("wind_up")

	source.visual.play("dash")
	var approach := create_tween()
	approach.tween_property(source.visual, "global_position", targets[0].visual.global_position, 0.2)
	await approach.finished

	await source.visual.play_and_wait("attack")

	for target in targets:
		var vfx_pos := target.visual.global_position
		hit_vfx.global_position = vfx_pos
		hit_vfx.restart()
		target.visual.play_hurt()

	sfx_player.play("impact")
	await get_tree().create_timer(hit_vfx.lifetime).timeout

	source.visual.play("recover")
	var recover := create_tween()
	recover.tween_property(source.visual, "global_position", source.visual.home_position, 0.2)
	await recover.finished

	queue_free()
```

Note `execute()` has no `signal animation_finished` — `ActionAnimator` uses `await scene.execute(...)` directly, which works because `execute()` is an async function that returns when done.

- [ ] **Step 3: Add child nodes to the scene**

The scene tree (script already embedded on root from Step 2):

```
UskravAnim (Node3D, embedded script)
├── HitVFX (CPUParticles3D)
│     one_shot = true
│     emitting = false
│     lifetime = 0.4
│     amount = 12
└── SFXPlayer (AnimationPlayer)
      [no audio yet — add method call tracks here when SFX assets exist]
```

Set `HitVFX` to a basic particle burst (sphere mesh, bright color). Exact values don't matter for the proof of concept — just enough to see something.

- [ ] **Step 4: Verify — run the scene end-to-end**

Run the main scene. Select Uskrav in the action menu. Expected behavior:

1. `ActionAnnouncer` shows "Uskrav"
2. Caster sprite plays `wind_up`, then `dash` while tweening toward the target
3. Caster plays `attack`
4. Particle burst appears at the target's position; target sprite plays `hurt`
5. Caster plays `recover` while tweening back to home position
6. Turn ends normally

Check the log for any warnings (missing animation names, etc.) and fix.

- [ ] **Step 5: Commit**

```bash
git add resources/mnemonics/uskrav/uskrav_anim.tscn \
        resources/characters/
git commit -m "feat: Uskrav animation scene — first end-to-end skill presentation"
```

---

## Self-Review

**Spec coverage:**
- ✅ `CharacterVisualComponent` — Task 1
- ✅ `play_and_wait()` interface — Task 1
- ✅ Base state / vitals sync — Task 1
- ✅ `home_position` captured in `_ready()` — Task 1
- ✅ Mnemonic folder restructure — Task 2
- ✅ `ActionAnimator` — Task 3
- ✅ Convention path — Task 3
- ✅ Fallback for missing scenes — Task 3
- ✅ `action_executed` carries mnemonic — Task 3
- ✅ `ActionPipeline` awaits animation — Task 4
- ✅ Uskrav proof-of-concept scene — Task 5
- ✅ AoE loop over targets in animation scene — Task 5
- ✅ SFX via AnimationPlayer only — Task 5 (SFXPlayer node, no audio calls in script)
- ✅ Animation script embedded in scene, not a separate .gd — Task 5

**Not in scope (per spec):**
- Camera movement
- Damage number floaters (already wired via `combat_text_shown`)
- DoT tick visuals
