extends Node

@onready var screen_fader: ScreenFader = $ScreenFader
@onready var current_scene: Node =  $CurrentScene

@export var starting_zone: PackedScene

var current_overworld: Node = null
var _overworld_camera: Camera3D
var _current_combat: CombatScene = null
var state: Enums.GameState = Enums.GameState.MAINMENU
var _pawn: PlayerOverworld = null

#PRELOADS
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/UI/main_menu.tscn")
const COMBAT_SCENE: PackedScene = preload("res://scenes/combat/combat_scene.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player_overworld.tscn")

func _ready() -> void:
	CombatEvents.encounter_triggered.connect(_on_encounter_triggered)
	if Globals.dev_mode == true:
		start_new_game()
	else:
		_show_main_menu()

func _show_main_menu() -> void:
	state =  Enums.GameState.MAINMENU
	var menu_instance: MainMenuController = MAIN_MENU_SCENE.instantiate()
	current_scene.add_child(menu_instance)
	Log.info("Displaying Main Menu")

func _clear_current_scene() -> void:
	for child in current_scene.get_children():
		child.queue_free()
	
func start_new_game() -> void:
	Log.info("New Game selected. Loading...")
	PartyManager.start_new_game()
	await screen_fader.fade_out()
	_clear_current_scene()
	_load_overworld(starting_zone)
	await screen_fader.fade_in()
	state = Enums.GameState.OVERWORLD
	Log.info("New Game started!")

func _load_overworld(zone: PackedScene) -> void:
	var instance: Node = zone.instantiate()
	current_scene.add_child(instance)
	current_overworld = instance
	if _pawn == null:
		_pawn = PLAYER_SCENE.instantiate()
		add_child(_pawn)
	var marker = instance.get_node_or_null("SpawnPoints/default")
	if marker == null:
		_pawn.global_position = Vector3.ZERO
		Log.warn("Default Spawn point missing. Placing Player on fallback.")
	else:
		_pawn.global_position = marker.global_position
	var zone_camera = instance.get_node_or_null("System/Camera3D")
	if zone_camera == null:
		Log.warn("Camera missng. Undable to set up CameraAnchor")
	else:
		var anchor = _pawn.get_node_or_null("CameraAnchor")
		if anchor == null:
			Log.warn("CameraAnchor is missing. Unable to set up ZoneCamera")
		else:
			anchor.remote_path = anchor.get_path_to(zone_camera)

func _on_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	if state != Enums.GameState.OVERWORLD:
		return
	Log.info("Encounter triggered, transitioning to combat")
	current_overworld.process_mode = Node.PROCESS_MODE_DISABLED
	_pawn.process_mode = Node.PROCESS_MODE_DISABLED
	_overworld_camera = get_viewport().get_camera_3d()
	await screen_fader.fade_out()
	state = Enums.GameState.COMBAT
	_current_combat = COMBAT_SCENE.instantiate()
	add_child(_current_combat)
	_current_combat.initialize(composition, environment, bgm)
	await screen_fader.fade_in()

func end_combat() -> void:
	Log.info("Combat finished, transitioning to overworld")
	await screen_fader.fade_out()
	_current_combat.queue_free()
	_current_combat = null
	if _overworld_camera != null:
		_overworld_camera.make_current()
	current_overworld.process_mode = Node.PROCESS_MODE_INHERIT
	_pawn.process_mode = Node.PROCESS_MODE_INHERIT
	await screen_fader.fade_in()
	state = Enums.GameState.OVERWORLD
