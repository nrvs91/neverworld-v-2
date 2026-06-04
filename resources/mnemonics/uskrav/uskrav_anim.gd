extends Node3D

signal hit_frame

var _source: CombatCharacter
var _targets: Array[CombatCharacter] = []

@onready var hit_vfx: CPUParticles3D = $HitVFX
@onready var charge_up_vfx: Node3D = $charge_up
@onready var vfx_timeline: AnimationPlayer = $VFXTimeline

func execute(source: CombatCharacter, targets: Array[CombatCharacter]) -> void:
	_source = source
	_targets = targets

	# Phase 1: WindUp + ChargeUp start together, sprite holds last frame
	source.visual.play("Combat_WindUp")
	charge_up_vfx.play()
	await charge_up_vfx.finished
	charge_up_vfx.queue_free()

	# Phase 2: Dash to target
	source.visual.play("Combat_Dash")
	var approach := create_tween()
	approach.tween_property(source.visual, "global_position", targets[0].visual.global_position, 0.2)
	await approach.finished

	# Phase 3: Melee1 + hit VFX
	await source.visual.play_and_wait("Combat_Melee1")

	_on_hit_impact()
	await get_tree().create_timer(0.4).timeout

	# Phase 4: Recover back home
	source.visual.play("Combat_Recover")
	var recover := create_tween()
	recover.tween_property(source.visual, "global_position", source.visual.home_position, 0.2)
	await recover.finished

	queue_free()

func _on_hit_impact() -> void:
	#hit_vfx.restart()
	for target in _targets:
		target.visual.play_hurt()
	hit_frame.emit()
