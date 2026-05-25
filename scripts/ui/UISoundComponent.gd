class_name UISoundComponent
extends Node

@export var nav_stream: AudioStream = null
@export var confirm_stream: AudioStream = null
@export var cancel_stream: AudioStream = null
@export var back_stream: AudioStream = null
@export var info_stream: AudioStream = null

var _players: Dictionary = {}

func _ready() -> void:
	_ensure_player(&"nav", nav_stream)
	_ensure_player(&"confirm", confirm_stream)
	_ensure_player(&"cancel", cancel_stream)
	_ensure_player(&"back", back_stream)
	_ensure_player(&"info", info_stream)

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
