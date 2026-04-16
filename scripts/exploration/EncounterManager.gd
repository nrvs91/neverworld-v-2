class_name EncounterManager
extends Node

@onready var step_counter: StepCounter = $StepCounter
@onready var encounter_pool: EncounterPool = $EncounterPool
@onready var combat_environment: CombatEnvironment = $CombatEnvironment
@onready var combat_bgm: CombatBGM = $CombatBGM

func _ready() -> void:
	Log.info("EncounterManager ready")
	step_counter.threshold_reached.connect(_on_threshold_reached)

func _on_threshold_reached() -> void:
	var composition := encounter_pool.pick()
	if composition == null:
		return
	CombatEvents.encounter_triggered.emit(
		composition,
		combat_environment.scene,
		combat_bgm.stream,
	)
