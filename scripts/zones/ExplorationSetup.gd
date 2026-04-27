extends Node
class_name ExplorationSetup

@onready var exploration_environment: ExplorationEnvironment = $ExplorationEnvironment
@onready var exploration_bgm: ExplorationBGM = $ExplorationBGM

func _ready() -> void:
	Log.info("ExplorationSetup ready.")

func pause_for_combat() -> void:
	exploration_bgm.stop()

func resume_after_combat() -> void:
	exploration_bgm.play()
