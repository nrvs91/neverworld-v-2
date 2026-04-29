class_name VitalsComponent
extends Node
var cur_hp: int = 0
var cur_mp: int = 0
var cur_ap: int = 0

var _max_hp: int = 0
var _max_mp: int = 0

func setup(hp: int, mp: int) -> void:
	_max_hp = hp
	_max_mp = mp
	cur_hp = hp #isnt this always setting up current hp to max HP? reseting HP/MP?
	cur_mp = mp
	cur_ap = 3 #will it be possible to tweak this for bosses or modify this with some buffs, from gear, so you enter combat with more/less AP?
	Log.info("ready")
func reset() -> void:
	cur_ap = 3
	Log.info("reset")


## this component will later hold all methods regarding spending/gaining etc, of the resources
## examples:
## func take_damage(amount: int) -> void
## func heal(amount: int) -> void                                                                                                   
## func spend_mp(cost: int) -> void
## func restore_mp(amount: int) -> void                                                                                             
## func spend_ap(cost: int) -> void    
## func gain_ap(amount: int = 1) -> void    # called by turn manager on TurnStart                                                   
## func can_afford_ap(cost: int) -> bool         
								
## Plus signals so the UI and execution state can react without polling:                                                            
## signal hp_changed(new_hp: int, max_hp: int)                                                                                      
## signal mp_changed(new_mp: int, max_mp: int)                                                                                      
## signal ap_changed(new_ap: int)                                                                                                   
## signal downed              
	  
