extends Node3D

@export var movement: MovementComponent
@export var player_input: PlayerInputComponent
#@export var npc_behaviour: NPCBehaviourComponent
@export var is_player := true

func _ready() -> void:
	Log.info("Initializing...")
	if is_player:
		movement.controller = player_input
		#npc_behaviour.queue_free()
	#else:
		#movement.controller = npc_behaviour
		#player_input.queue_free()
