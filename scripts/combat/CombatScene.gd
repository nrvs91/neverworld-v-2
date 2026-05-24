class_name CombatScene
extends Node

@onready var player_spawner: PlayerSpawner = $PlayerSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var environment_mount: Node3D = $EnvironmentMount
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var combat_camera: Camera3D = $Camera3D
@onready var logic_fsm: CombatFSM = $CombatFSM
@onready var ui_fsm: CombatUIFSM = $CombatUIFSM
@onready var action_pipeline: ActionPipeline = $ActionPipeline
@onready var _player_party_anchor: Marker3D = $Anchors/PlayerPartyAnchor
@onready var _enemy_party_anchor: Marker3D = $Anchors/EnemyPartyAnchor
@onready var _middle_anchor: Marker3D = $Anchors/MiddleAnchor

func _exit_tree() -> void:
	CombatAnchors.clear()

func _clear_environment() -> void:
	for child in environment_mount.get_children():
		child.queue_free()

func initialize(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	combat_camera.make_current()
	_clear_environment()
	player_spawner.initialize()
	enemy_spawner.initialize(composition)
	CombatAnchors.register(_player_party_anchor, _enemy_party_anchor, _middle_anchor)
	if environment:
		environment_mount.add_child(environment.instantiate())
	if bgm:
		bgm_player.stream = bgm
		bgm_player.play()
	await get_tree().process_frame
	var all_actors: Array = player_spawner.get_all_characters() + enemy_spawner.get_all_characters()
	Log.info("CombatScene — actors ready:", all_actors.size())
	ui_fsm.start(all_actors)
	logic_fsm.start(all_actors, action_pipeline)
