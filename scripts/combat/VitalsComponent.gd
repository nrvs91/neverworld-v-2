class_name VitalsComponent
extends Node

const AP_CAP: int = 10

var cur_hp: int = 0
var cur_mp: int = 0
var cur_ap: int = 0
var cur_ct: float = 0.0

var _max_hp: int = 0
var _max_mp: int = 0

## FUTURE: signature grows to setup(max_hp, max_mp, cur_hp, cur_mp) once the persistence
##   loop exists. cur_hp / cur_mp come from CharacterSaveData and survive across encounters
##   (dungeon attrition pillar). Also needs CombatEnd to write cur_hp / cur_mp back to
##   CharacterSaveData — without that writeback, persistence is one-directional.

func setup(max_hp: int, max_mp: int) -> void:
	_max_hp = max_hp
	_max_mp = max_mp
	cur_hp = max_hp
	cur_mp = max_mp
	cur_ap = 3
	cur_ct = 0.0
	Log.debug("VitalsComponent setup")

func reset() -> void:
	cur_ap = 3
	Log.debug("VitalsComponent reset")

func is_downed() -> bool:
	return cur_hp <= 0

func gain_ap(amount: int) -> void:
	cur_ap = min(cur_ap + amount, AP_CAP)

func take_damage(amount: int) -> void:
	cur_hp = max(0, cur_hp - amount)
	if cur_hp == 0:
		Log.info("HP reached zero")
