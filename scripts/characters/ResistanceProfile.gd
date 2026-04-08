class_name ResistanceProfile
extends Resource

# Resistance state per damage/ailment type.
# Authored directly on enemies. Compiled from gear for players at combat start.
# Tokens reference this resource when granting temporary RESISTANT or WEAK states.
# IMMUNE cannot be overwritten by tokens — only BYPASS skills ignore it.

@export_group("Physical")
@export var slash: ResistanceType.State = ResistanceType.State.NONE
@export var pierce: ResistanceType.State = ResistanceType.State.NONE
@export var blunt: ResistanceType.State = ResistanceType.State.NONE

@export_group("Elemental")
@export var fire: ResistanceType.State = ResistanceType.State.NONE
@export var water: ResistanceType.State = ResistanceType.State.NONE
@export var air: ResistanceType.State = ResistanceType.State.NONE
@export var nature: ResistanceType.State = ResistanceType.State.NONE
@export var stone: ResistanceType.State = ResistanceType.State.NONE
@export var feral: ResistanceType.State = ResistanceType.State.NONE

@export_group("Ailments")
@export var bleed: ResistanceType.State = ResistanceType.State.NONE
@export var stun: ResistanceType.State = ResistanceType.State.NONE


func get_state(type: ResistanceType.DamageType) -> ResistanceType.State:
	match type:
		ResistanceType.DamageType.Slash:   return slash
		ResistanceType.DamageType.Pierce:  return pierce
		ResistanceType.DamageType.Blunt:   return blunt
		ResistanceType.DamageType.Fire:    return fire
		ResistanceType.DamageType.Water:   return water
		ResistanceType.DamageType.Air:     return air
		ResistanceType.DamageType.Nature:  return nature
		ResistanceType.DamageType.Stone:   return stone
		ResistanceType.DamageType.Feral:   return feral
		ResistanceType.DamageType.Bleed:   return bleed
		ResistanceType.DamageType.Stun:    return stun
	return ResistanceType.State.NONE
