class_name CombatCharacter
extends Node3D

@onready var vitals: VitalsComponent = $VitalsComponent
@onready var tokens: ActiveTokens = $ActiveTokens
@onready var visuals: CombatVisuals = $CombatVisuals
@onready var sfx: CombatSFXComponent = $CombatSFXComponent
