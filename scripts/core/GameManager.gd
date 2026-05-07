extends Node

@onready var screen_fader: ScreenFader = $ScreenFader
@onready var current_scene: Node =  $CurrentScene

@export var starting_area: Area

var current_exploration: Node = null
var _exploration_camera: Camera3D
var _current_combat: CombatScene = null
var state: Enums.GameState = Enums.GameState.MAINMENU
var _pawn: PlayerExploration = null

#PRELOADS
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/UI/main_menu.tscn")
const COMBAT_SCENE: PackedScene = preload("res://scenes/combat/combat_scene.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player_exploration.tscn")

func _ready() -> void:
	ExplorationEvents.zone_exit_requested.connect(_on_zone_exit_requested)
	CombatEvents.encounter_triggered.connect(_on_encounter_triggered)
	if Globals.dev_mode == true:
		start_new_game()
	else:
		_show_main_menu()

func _show_main_menu() -> void:
	state =  Enums.GameState.MAINMENU
	var menu_instance: MainMenuController = MAIN_MENU_SCENE.instantiate()
	current_scene.add_child(menu_instance)
	Log.info("displaying main menu")

func _clear_current_scene() -> void:
	for child in current_scene.get_children():
		child.queue_free()
	
func start_new_game() -> void:
	Log.info("new game loading")
	PartyManager.start_new_game()
	await screen_fader.fade_out()
	_clear_current_scene()
	_load_zone(starting_area.entry_zone)
	await screen_fader.fade_in()
	state = Enums.GameState.EXPLORATION
	Log.info("new game started")

func _load_zone(zone: PackedScene, spawn_point: StringName = &"default") -> void:
	if zone == null:
		Log.error("_load_zone called with null zone")
		return
	if current_exploration != null:
		current_exploration.queue_free()
		current_exploration = null
	var instance: Node = zone.instantiate()
	current_scene.add_child(instance)
	current_exploration = instance
	if _pawn == null:
		_pawn = PLAYER_SCENE.instantiate()
		add_child(_pawn)
	var marker = instance.get_node_or_null("SpawnPoints/" + spawn_point)
	if marker == null:
		_pawn.global_position = Vector3.ZERO
		Log.warn("spawn point missing, using fallback")
	else:
		_pawn.global_position = marker.global_position

func _on_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	if state != Enums.GameState.EXPLORATION:
		return
	Log.info("encounter triggered")
	state = Enums.GameState.TRANSITION
	current_exploration.process_mode = Node.PROCESS_MODE_DISABLED
	_pawn.process_mode = Node.PROCESS_MODE_DISABLED
	_exploration_camera = get_viewport().get_camera_3d()
	await screen_fader.fade_out()
	state = Enums.GameState.COMBAT
	_current_combat = COMBAT_SCENE.instantiate()
	add_child(_current_combat)
	_current_combat.initialize(composition, environment, bgm)
	await screen_fader.fade_in()

func end_combat() -> void:
	if state != Enums.GameState.COMBAT:
		Log.warn("end_combat called outside of COMBAT")
		return
	Log.info("combat finished")
	state = Enums.GameState.TRANSITION
	await screen_fader.fade_out()
	_current_combat.queue_free()
	_current_combat = null
	if _exploration_camera != null:
		_exploration_camera.make_current()
	current_exploration.process_mode = Node.PROCESS_MODE_INHERIT
	_pawn.process_mode = Node.PROCESS_MODE_INHERIT
	await screen_fader.fade_in()
	state = Enums.GameState.EXPLORATION

func _on_zone_exit_requested(target_zone: PackedScene, target_spawn_point: StringName) -> void:
	if state != Enums.GameState.EXPLORATION:
		Log.warn("zone exit ignored, not in EXPLORATION state")
		return
	Log.info("zone exit, loading:", target_zone.resource_path)
	state = Enums.GameState.TRANSITION
	await screen_fader.fade_out()
	_load_zone(target_zone, target_spawn_point)
	await screen_fader.fade_in()
	state = Enums.GameState.EXPLORATION
