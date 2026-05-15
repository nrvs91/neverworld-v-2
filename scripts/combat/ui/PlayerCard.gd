class_name PlayerCard
extends Control

const NUDGE_AMOUNT: float = 12.0
const NUDGE_DURATION: float = 0.12

@onready var hp_bar: TextureProgressBar = $VBox/TopBar/HPBar
@onready var mp_bar: TextureProgressBar = $VBox/TopBar/MPBar
@onready var ap_bar: TextureProgressBar = $VBox/APBar
@onready var hp_value: Label = $VBox/TopBar/HPBar/HP/HPValue
@onready var mp_value: Label = $VBox/TopBar/MPBar/MP/MPValue
@onready var ap_value: Label = $VBox/APBar/AP/APValue
@onready var portrait_rect: TextureRect = $VBox/Portrait/Portrait

var _actor: CombatCharacter = null

func setup(actor: CombatCharacter) -> void:
	_actor = actor
	hp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxHP)
	mp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxMP)
	ap_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxAP)
	actor.vitals.vitals_changed.connect(refresh_vitals)
	# portrait_rect.texture = actor.portrait_texture
	# Uncomment once portrait_texture is added to CombatCharacter
	refresh_vitals()

func refresh_vitals() -> void:
	if _actor == null:
		return
	hp_bar.value = _actor.vitals.cur_hp
	mp_bar.value = _actor.vitals.cur_mp
	ap_bar.value = _actor.vitals.cur_ap
	hp_value.text = str(_actor.vitals.cur_hp)
	mp_value.text = str(_actor.vitals.cur_mp)
	ap_value.text = str(_actor.vitals.cur_ap)

func set_inactive() -> void:
	modulate.a = 0.5

func nudge(enabled: bool) -> void:
	var target_y: float = NUDGE_AMOUNT if enabled else 0.0
	var tween := create_tween()
	tween.tween_property(self, "offset_top", -target_y, NUDGE_DURATION)
