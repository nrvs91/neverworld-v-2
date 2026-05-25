extends ColorRect

var _entry_tween: Tween = null
var _breathe_tween: Tween = null
var _focus_count: int = 0

func _ready():
	var parent = get_parent()
	if parent is BaseButton:
		parent.focus_entered.connect(_on_focus_in)
		parent.mouse_entered.connect(_on_focus_in)
		parent.focus_exited.connect(_on_focus_out)
		parent.mouse_exited.connect(_on_focus_out)

func _on_focus_in():
	_focus_count += 1
	if _focus_count > 1:
		return
	_kill_entry_tween()
	_stop_breathing()
	var current: float = material.get_shader_parameter("focus_progress")
	_entry_tween = create_tween()
	_entry_tween.set_ease(Tween.EASE_IN_OUT)
	_entry_tween.set_trans(Tween.TRANS_SINE)
	_entry_tween.tween_method(_apply_progress, current, 1.0, 0.25)
	_entry_tween.tween_callback(_start_breathing)

func _on_focus_out():
	_focus_count = max(0, _focus_count - 1)
	if _focus_count > 0:
		return
	_kill_entry_tween()
	_stop_breathing()
	var current: float = material.get_shader_parameter("focus_progress")
	_entry_tween = create_tween()
	_entry_tween.set_ease(Tween.EASE_IN_OUT)
	_entry_tween.set_trans(Tween.TRANS_SINE)
	_entry_tween.tween_method(_apply_progress, current, 0.0, 0.25)

func _start_breathing():
	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.tween_interval(0.25)
	_breathe_tween.tween_method(_apply_progress, 1.0, 0.0, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_breathe_tween.tween_method(_apply_progress, 0.0, 1.0, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_breathing():
	if _breathe_tween and _breathe_tween.is_valid():
		_breathe_tween.kill()

func _kill_entry_tween():
	if _entry_tween and _entry_tween.is_valid():
		_entry_tween.kill()

func _apply_progress(value: float):
	material.set_shader_parameter("focus_progress", value)
