# Combat Anchor System + Approach/Recover Motion

## Status
Approved — ready for implementation.

## What Already Exists
- `MiddleAnchor`, `PlayerPartyAnchor`, `EnemyPartyAnchor` — three `Marker3D` nodes already placed manually in `combat_scene.tscn` under an `Anchors` parent node.
- `CombatVisuals.gd` — `approach()` and `recover()` exist as stubs; `_action_playing` bool is already declared.
- `MnemonicResource.is_melee: bool` — already exists, gates motion.

## What Gets Built

### 1. CombatAnchors Autoload
New file: `scenes/combat/combat_anchors.tscn` + `scripts/combat/CombatAnchors.gd`

Holds three named Node3D references, registered by CombatScene at combat start:

```gdscript
var player_party: Node3D
var enemy_party: Node3D
var middle: Node3D

func register(p: Node3D, e: Node3D, m: Node3D) -> void:
    player_party = p
    enemy_party = e
    middle = m

func clear() -> void:
    player_party = null
    enemy_party = null
    middle = null
```

Registered in `project.godot` autoloads as `CombatAnchors`.

### 2. CombatScene Registration
`CombatScene.gd` gets three new `@onready` refs to the anchor nodes:

```gdscript
@onready var _player_party_anchor: Marker3D = $Anchors/PlayerPartyAnchor
@onready var _enemy_party_anchor: Marker3D = $Anchors/EnemyPartyAnchor
@onready var _middle_anchor: Marker3D = $Anchors/MiddleAnchor
```

`initialize()` registers them with CombatAnchors after spawning:
```gdscript
CombatAnchors.register(_player_party_anchor, _enemy_party_anchor, _middle_anchor)
```

`_exit_tree()` calls `CombatAnchors.clear()`.

### 3. CombatVisuals — approach() and recover()
Both methods are async (callers await them). The tween moves `self.position` in local space — CombatVisuals is a child of CombatCharacter, so local position delta equals world-space delta (no rotation on characters).

```gdscript
var _home: Vector3

func approach(target_global_pos: Vector3, duration: float = 0.2) -> void:
    _home = position
    _action_playing = true
    var delta := target_global_pos - global_position
    var destination := _home + delta * 0.7  # close but not overlapping
    var tween := create_tween()
    tween.tween_property(self, "position", destination, duration)
    await tween.finished

func recover(duration: float = 0.2) -> void:
    var tween := create_tween()
    tween.tween_property(self, "position", _home, duration)
    await tween.finished
    _action_playing = false
```

### 4. ActionPipeline — Motion Integration
Approach fires after validation passes (action is confirmed to execute), before `SkillExecutor.execute()`. Recover fires immediately after. Both gated by `mnemonic.is_melee`.

Position used: `target.get_parent().global_position` — the target's slot node, which is the stable world-space anchor for that character.

```gdscript
# After _can_execute() passes and resources are spent:
if mnemonic.is_melee:
    await attacker.visuals.approach(target.get_parent().global_position)

SkillExecutor.execute(context)

if mnemonic.is_melee:
    await attacker.visuals.recover()

# Existing 0.4s pause for damage numbers follows here
```

Non-melee skills: no motion, no change to existing timing.

## Slot Positions (No Change)
Character slot positions are accessed directly as `character.get_parent().global_position` wherever needed. No registration in CombatAnchors required — the slot-to-character relationship is stable and readable from the scene tree.

## Future Extension Point
When non-melee visual motion is needed (cast lean, ranged step), `is_melee: bool` becomes a `VisualType` enum on `MnemonicResource`. The ActionPipeline gate expands to a match block. CombatVisuals gains the new motion methods. No structural changes.

## Files Touched
- `scripts/combat/CombatAnchors.gd` — new
- `scenes/combat/combat_anchors.tscn` — new
- `project.godot` — add CombatAnchors autoload
- `scripts/combat/CombatScene.gd` — register/clear anchors
- `CombatVisuals.gd` — implement approach() and recover()
- `scripts/combat/ActionPipeline.gd` — add motion calls
