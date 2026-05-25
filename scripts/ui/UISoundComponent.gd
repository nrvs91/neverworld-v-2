class_name UISoundComponent
extends Node

@export var nav_stream: AudioStream = null
@export var confirm_stream: AudioStream = null
@export var cancel_stream: AudioStream = null
@export var back_stream: AudioStream = null
@export var info_stream: AudioStream = null

var _players: Dictionary = {}

func _auto_wire() -> void:
	var p := get_parent()
	# BaseButton: focus = nav, press = confirm
	if p is BaseButton:
		p.focus_entered.connect(play_nav)
		p.pressed.connect(play_confirm)
		return
	# Cursor-like: hover = nav, confirmed = confirm, cancelled = cancel
	# Use string-based connect — p is Node-typed, signal access goes through Object.connect()
	if p.has_signal(&"hover_changed"):
		p.connect(&"hover_changed", _on_hover_changed)
	if p.has_signal(&"target_confirmed"):
		p.connect(&"target_confirmed", _on_target_confirmed)
	if p.has_signal(&"target_cancelled"):
		p.connect(&"target_cancelled", play_cancel)

func _on_hover_changed(_old: Variant, _new: Variant) -> void:
	play_nav()

func _on_target_confirmed(_target: Variant) -> void:
	play_confirm()

func _ready() -> void:
	_ensure_player(&"nav", nav_stream)
	_ensure_player(&"confirm", confirm_stream)
	_ensure_player(&"cancel", cancel_stream)
	_ensure_player(&"back", back_stream)
	_ensure_player(&"info", info_stream)
	_auto_wire()

func play_nav() -> void:
	_play(&"nav")

func play_confirm() -> void:
	_play(&"confirm")

func play_cancel() -> void:
	_play(&"cancel")

func play_back() -> void:
	_play(&"back")

func play_info() -> void:
	_play(&"info")

func set_stream(key: StringName, stream: AudioStream) -> void:
	_ensure_player(key, stream)

func _ensure_player(key: StringName, stream: AudioStream) -> void:
	if stream == null or _players.has(key):
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Master"
	add_child(player)
	_players[key] = player

func _play(key: StringName) -> void:
	var player: AudioStreamPlayer = _players.get(key)
	if player:
		player.play()
