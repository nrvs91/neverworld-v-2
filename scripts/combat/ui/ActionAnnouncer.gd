class_name ActionAnnouncer
extends ColorRect

const DISPLAY_DURATION: float = 0.5

@onready var _text: Label = $ActionText

func _ready() -> void:
	hide()
	CombatEvents.action_announced.connect(_on_action_announced)

func _on_action_announced(text: String) -> void:
	_text.text = text
	show()
	await get_tree().create_timer(DISPLAY_DURATION).timeout
	hide()
