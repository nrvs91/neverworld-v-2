class_name CombatScene
extends Node

@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var combat_camera: Camera3D = $Camera3D
@onready var character_card: CharacterCard = $CombatUI/CharacterCard

func _clear_environment() -> void:
	for child in environment_mount.get_children():                                         
		child.queue_free()

func initialize(composition: CombatConfig, environment: PackedScene, bgm: AudioStream):
	combat_camera.make_current()
	_clear_environment()
	player_spawner.initialize()
	var character := player_spawner.get_character(0)
	if character and character_card:
		character_card.display(character)
	enemy_spawner.initialize(composition)
	if environment:
		environment_mount.add_child(environment.instantiate())
	if bgm:
		bgm_player.stream = bgm
		bgm_player.play()
	Log.debug("ready")
