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
    cur_hp = hp #isnt this always setting up current hp to max HP? resseting HP/MP?
    cur_mp = mp
    cur_ap = 3 #will it be possible to tweak this for bosses or modify this with some buffs, from gear, so you enter combat with more/less AP?
    Log.info("VitalsComponent setup - HP:", cur_hp, "MP:", cur_mp) #big issue here! also, we'd need the characters name as well...

func reset() -> void:
    cur_ap = 3
    Log.info("VitalsComponent reset - AP = 3")
