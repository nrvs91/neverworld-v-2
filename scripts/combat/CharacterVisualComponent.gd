class_name CharacterVisualComponent
extends Node3D

enum Base { IDLE, LOW_HP, KO }

const LOW_HP_THRESHOLD := 0.25

var home_position: Vector3
var sprite: AnimatedSprite3D
var _base: Base = Base.IDLE
var _vitals: VitalsComponent

func setup(vitals: VitalsComponent, sprite_frames: SpriteFrames) -> void:
	_vitals = vitals
	_vitals.vitals_changed.connect(_on_vitals_changed)
	sprite.sprite_frames = sprite_frames
	_restore_base()

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
	if not sprite.is_playing():
		return
	await sprite.animation_finished

func play_hurt() -> void:
	play("Combat_Hurt")
	if sprite.is_playing():
		await sprite.animation_finished
	_restore_base()

func attach_presentation(scene: Node3D) -> void:
	add_child(scene)

func set_base(state: Base) -> void:
	_base = state
	_restore_base()

func _restore_base() -> void:
	match _base:
		Base.IDLE:   play("Combat_Idle")
		Base.LOW_HP: play("Combat_Idle")
		Base.KO:     play("Combat_Idle")

func _on_vitals_changed() -> void:
	if _vitals.is_downed():
		set_base(Base.KO)
	elif _vitals.cur_hp < _vitals.max_hp * LOW_HP_THRESHOLD:
		set_base(Base.LOW_HP)
	else:
		set_base(Base.IDLE)
