class_name CombatScene
extends Node

@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var combat_camera: Camera3D = $Camera3D
@onready var character_card: CharacterCard = $CombatUI/CharacterCard
@onready var logic_fsm: CombatFSM = $CombatFSM

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
	await get_tree().process_frame
	var all_actors: Array = player_spawner.get_all_characters() + enemy_spawner.get_all_characters()
	Log.info("CombatScene — actors ready:", all_actors.size())
	logic_fsm.start(all_actors)
