@tool
class_name ExplorationSetup
extends Node

@onready var exploration_environment: ExplorationEnvironment = $ExplorationEnvironment
@onready var exploration_bgm: ExplorationBGM = $ExplorationBGM

func _ready() -> void:
	if Engine.is_editor_hint():
		exploration_environment.enter()
		return
	Log.info("ready")

func enter() -> void:
	exploration_environment.enter()
	exploration_bgm.play()

func exit() -> void:
	exploration_environment.exit()
	exploration_bgm.stop()

func pause_for_combat() -> void:
	exploration_bgm.stop()
	exploration_environment.hide_geometry()

func resume_after_combat() -> void:
	exploration_bgm.play()
	exploration_environment.show_geometry()
