class_name ActionAnimator
extends Node

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

func _ready() -> void:
	CombatEvents.action_executed.connect(_on_action_executed, CONNECT_DEFERRED)

func _exit_tree() -> void:
	CombatEvents.action_executed.disconnect(_on_action_executed)

func _on_action_executed(source: CombatCharacter, targets: Array[CombatCharacter], _damage: int, mnemonic: MnemonicRes) -> void:
	if mnemonic == null:
		CombatEvents.action_hit_frame.emit()
		CombatEvents.action_animation_complete.emit()
		return

	var id := mnemonic.mnemonic_name.to_lower().replace(" ", "_")
	var path := "res://resources/mnemonics/%s/%s_anim.tscn" % [id, id]

	if not ResourceLoader.exists(path):
		Log.warn("ActionAnimator — no animation scene for", id)
		CombatEvents.action_hit_frame.emit()
		CombatEvents.action_animation_complete.emit()
		return

	Log.info("ActionAnimator — playing", id)
	var scene = load(path).instantiate()
	source.visual.attach_presentation(scene)
	if scene.has_signal("hit_frame"):
		scene.hit_frame.connect(func(): CombatEvents.action_hit_frame.emit())
	await scene.execute(source, targets)
	source.visual.play("Combat_Idle")
	for target in targets:
		target.visual.play("Combat_Idle")
	CombatEvents.action_animation_complete.emit()
