class_name InfoPanel
extends PanelContainer

@onready var info_label: Label = $InfoLabel

func show_text(text: String) -> void:
	info_label.text = text
	visible = true

func hide_panel() -> void:
	visible = false
