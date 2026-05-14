extends ColorRect


func _ready():
	var parent = get_parent()
	
	if parent is BaseButton:
		parent.focus_entered.connect(_set_inverted.bind(true))
		parent.mouse_entered.connect(_set_inverted.bind(true))
		parent.focus_exited.connect(_set_inverted.bind(false))
		parent.mouse_exited.connect(_set_inverted.bind(false))

func _set_inverted(is_inverted: bool):
	material.set_shader_parameter("is_selected", is_inverted)
