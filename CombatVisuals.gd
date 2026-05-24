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
	if _action_playing:
		Log.warn("CombatVisuals — approach() called while action already playing")
		return
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
	if not _action_playing:
		Log.warn("CombatVisuals — recover() called without approach(), skipping")
		return
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
