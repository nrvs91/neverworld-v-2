extends Node

@onready var screen_fader: ScreenFader = $ScreenFader
@onready var combat_scene: CombatScene = $CombatScene
@onready var current_scene: Node =  $CurrentScene
var current_overworld: Node = null
var state: Enums.GameState = Enums.GameState.MAINMENU
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/UI/main_menu.tscn")

func _ready() -> void:
	CombatEvents.encounter_triggered.connect(_on_encounter_triggered)
	combat_scene.process_mode = Node.PROCESS_MODE_DISABLED
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
	_load_overworld("res://main.tscn")
	await screen_fader.fade_in()
	state = Enums.GameState.OVERWORLD
	Log.info("New Game started!")

func _load_overworld(path: String) -> void:
	var scene: PackedScene = load(path)
	var instance: Node = scene.instantiate()
	current_scene.add_child(instance)

func _on_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream) -> void:
	Log.info("Encounter triggered, transitioning to combat")
	if state != Enums.GameState.OVERWORLD:
		return
	current_overworld.process_mode = Node.PROCESS_MODE_DISABLED
	await screen_fader.fade_out()
	state = Enums.GameState.COMBAT
	combat_scene.process_mode = Node.PROCESS_MODE_INHERIT
	combat_scene.initialize(composition, environment, bgm)
	await screen_fader.fade_in()

	
