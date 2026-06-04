# Animation Scene Cheat Sheet

Every mnemonic gets one animation scene. It lives next to its `.tres`:

```
resources/mnemonics/uskrav/
  uskrav.tres
  uskrav_anim.tscn       ← embed the script on the root node, no separate .gd
```

## Vocabulary

These are the calls you have. Everything comes through `CharacterVisualComponent`:

```gdscript
# Play an animation, don't wait
source.visual.play("Combat_WindUp")

# Play an animation, wait until it finishes
await source.visual.play_and_wait("Combat_Melee1")

# Make the target flinch (fire-and-forget, auto-restores to idle)
target.visual.play_hurt()

# Move the caster
var t = create_tween()
t.tween_property(source.visual, "global_position", target.visual.global_position, 0.2)
await t.finished

# Move the caster back home
var t = create_tween()
t.tween_property(source.visual, "global_position", source.visual.home_position, 0.2)

# Fire a VFX
hit_vfx.global_position = target.visual.global_position
hit_vfx.emitting = true
await get_tree().create_timer(hit_vfx.lifetime).timeout
hit_vfx.emitting = false

# Wait for a signal from the pipeline
hit_frame.emit()          # tells ActionPipeline "apply damage now"

# Clean up when done
queue_free()
```

## The Pattern

Every animation scene does this:

```gdscript
extends Node3D

signal hit_frame

func execute(source: CombatCharacter, targets: Array[CombatCharacter]) -> void:
    # 1. WIND UP
    await source.visual.play_and_wait("Combat_WindUp")

    # 2. APPROACH
    source.visual.play("Combat_Dash")
    var approach = create_tween()
    approach.tween_property(source.visual, "global_position",
        targets[0].visual.global_position, 0.2)
    await approach.finished

    # 3. ATTACK + IMPACT
    await source.visual.play_and_wait("Combat_Melee1")
    hit_vfx.global_position = targets[0].visual.global_position
    hit_vfx.emitting = true
    for t in targets:
        t.visual.play_hurt()
    hit_frame.emit()
    await get_tree().create_timer(hit_vfx.lifetime).timeout

    # 4. RECOVER
    source.visual.play("Combat_Recover")
    var recover = create_tween()
    recover.tween_property(source.visual, "global_position",
        source.visual.home_position, 0.2)
    await recover.finished

    queue_free()
```

## Rules

- Always `queue_free()` at the end
- AoE: iterate `targets` for VFX placement and `play_hurt()`
- No AnimationPlayer for character animation — drive it in code
- No hardcoded timing (`create_timer(0.5)`) for sprite beats — use `play_and_wait`
- VFX nodes use their own `AnimationPlayer` for complex sub-timing if needed
- `hit_frame` signal is optional — only emit if the skill needs to apply damage at a specific animation beat (e.g. weapon contact frame). If you don't emit it, damage is applied at `action_executed` time.
