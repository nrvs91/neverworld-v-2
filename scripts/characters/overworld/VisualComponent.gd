# VisualComponent - Character Visual State Management
#
# Handles all visual presentation for a character:
#   - Animation state machine (Idle/Walk/Run)
#   - Directional facing (4-way + diagonals)
#   - Sprite flipping for left-facing
#
# LOGGING NOTES:
#   - Log.info on animation changes (state transitions)
#   - Log.debug on direction changes (high-frequency input)
#   - Log.info in _ready (component lifecycle)

extends Node3D
class_name VisualComponent

@export var controller: Node
@onready var sprite := $AnimatedSprite3D

var _direction := Vector2.ZERO
var _last_direction := Vector2.DOWN
var _is_running := false

func _ready() -> void:
	Log.info("Initializing...")
	controller.direction_changed.connect(_on_direction_changed)
	controller.run_toggled.connect(_on_run_toggled)

func _on_direction_changed(dir: Vector2) -> void:
	_direction = dir
	if dir != Vector2.ZERO:
		_last_direction = dir
	_play_animation()
	Log.debug("Direction changed to:", dir)

func _on_run_toggled(running: bool) -> void:
	_is_running = running
	_play_animation()
	Log.debug("Running:", running)

func _get_animation_direction(dir: Vector2) -> String:
	match [int(sign(dir.x)), int(sign(dir.y))]:
		[-1, 0]: return "Left"
		[1, 0]: return "Left"
		[0, -1]: return "Up"
		[0, 1]: return "Down"
		[-1, -1]: return "UpLeft"
		[-1, 1]: return "DownLeft"
		[1, -1]: return "UpLeft"
		[1, 1]: return "DownLeft"
	return "Down"

func _get_animation_prefix() -> String:
	if _direction == Vector2.ZERO:
		return "Idle"
	if _is_running:
		return "Run"
	return "Walk"

func _play_animation():
	var prefix = _get_animation_prefix()
	var direction = _get_animation_direction(_last_direction)
	sprite.flip_h = sign(_last_direction.x) == 1
	var anim = prefix + "_" + direction
	if sprite.animation == anim: 
		return
	sprite.play(anim)
	Log.info("Last direction:", _last_direction)
	Log.debug("Animation playing:", prefix, direction)
