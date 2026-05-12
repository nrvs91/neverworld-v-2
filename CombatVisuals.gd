class_name CombatVisuals
extends Node3D

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D #possible name change here

var _base_state: StringName = &"Idle"
var _action_playing: bool = false

func setup(sprite_frames: SpriteFrames) -> void:
	sprite.sprite_frames = sprite_frames
	if sprite_frames.has_animation(_base_state):
		sprite.play(_base_state)
	else:
		var fallback := sprite_frames.get_animation_names()[0]
		sprite.play(fallback)
		Log.warn("CombatVi suals: no Idle animation, playing", fallback)
	Log.info("CombatVisuals setup")

func set_base_state(state: StringName) -> void:
	_base_state = state
	if not _action_playing:
		sprite.play(_base_state)
	Log.debug("CombatVisuals base state set:", state)

func approach(target_offset: Vector3, duration: float = 0.2) -> void: #this will be the "dash" from attacker to target in melee skills
		Log.debug("CombatVisuals approach (stub)")

func recover(duration: float = 0.2) -> void: #this will be the "go back" from target to attackers position, altough maybe we can wrap this into a single function, GO>GOBACK kind of deal, like rewind?
		Log.debug("CombatVisuals recover (stub)")

#SIGNALS
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
