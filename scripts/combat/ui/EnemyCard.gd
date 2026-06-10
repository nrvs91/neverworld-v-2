class_name EnemyCard
extends Control

const NUDGE_AMOUNT: float = 12.0
const NUDGE_DURATION: float = 0.12

@onready var enemy_name: Label = $VBox/VBoxContainer/Enemy_Name
@onready var hp_bar: TextureProgressBar = $VBox/VBoxContainer/HPBar
@onready var _token_label: Label = $VBox/TokenContainer/TokenLabel

var _actor: CombatCharacter = null

func setup(actor: CombatCharacter) -> void:
	_actor = actor
	hp_bar.max_value = actor.stats.stat(CharacterStats.Stat.MaxHP)
	actor.vitals.vitals_changed.connect(refresh_vitals)
	actor.tokens.token_added.connect(_refresh_token_display)
	actor.tokens.token_removed.connect(_refresh_token_display)
	refresh_vitals()

func refresh_vitals() -> void:
	if _actor == null:
		return
	hp_bar.value = _actor.vitals.cur_hp

func _refresh_token_display(_token = null) -> void:
	_token_label.text = _actor.tokens.get_display_text()

func set_inactive() -> void:
	modulate.a = 0.5

func nudge(enabled: bool) -> void:
	var target_y: float = NUDGE_AMOUNT if enabled else 0.0
	var tween := create_tween()
	tween.tween_property(self, "offset_top", target_y, NUDGE_DURATION)
