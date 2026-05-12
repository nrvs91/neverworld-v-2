class_name EnemyCard
extends Control

const NUDGE_AMOUNT: float = 12.0
const NUDGE_DURATION: float = 0.12

@onready var hp_bar: TextureProgressBar = $VBox/TopBar/HPBar
@onready var mp_bar: TextureProgressBar = $VBox/TopBar/MPBar
@onready var ap_bar: TextureProgressBar = $VBox/APBar

var _actor: CombatCharacter = null

func setup(actor: CombatCharacter) -> void:
	_actor = actor
	hp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxHP)
	mp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxMP)
	ap_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxAP)
	refresh_vitals()

func refresh_vitals() -> void:
	if _actor == null:
		return
	hp_bar.value = _actor.vitals.cur_hp
	mp_bar.value = _actor.vitals.cur_mp
	ap_bar.value = _actor.vitals.cur_ap

func set_inactive() -> void:
	modulate.a = 0.5

func nudge(enabled: bool) -> void:
	var target_y: float = NUDGE_AMOUNT if enabled else 0.0
	var tween := create_tween()
	tween.tween_property(self, "offset_top", target_y, NUDGE_DURATION)
