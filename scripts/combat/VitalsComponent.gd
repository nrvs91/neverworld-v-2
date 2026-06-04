class_name VitalsComponent
extends Node

signal vitals_changed

const AP_CAP: int = 10

var cur_hp: int = 0
var cur_mp: int = 0
var cur_ap: int = 0
var cur_ct: float = 0.0

var max_hp: int = 0
var max_mp: int = 0

## FUTURE: signature grows to setup(max_hp, max_mp, cur_hp, cur_mp) once the persistence
##   loop exists. cur_hp / cur_mp come from CharacterSaveData and survive across encounters
##   (dungeon attrition pillar). Also needs CombatEnd to write cur_hp / cur_mp back to
##   CharacterSaveData — without that writeback, persistence is one-directional.

func setup(max_hp_val: int, max_mp_val: int) -> void:
	max_hp = max_hp_val
	max_mp = max_mp_val
	cur_hp = max_hp_val
	cur_mp = max_mp_val
	cur_ap = 0
	cur_ct = 0.0
	Log.debug("VitalsComponent setup")

func reset() -> void:
	cur_ap = 0
	Log.debug("VitalsComponent reset")

func is_downed() -> bool:
	return cur_hp <= 0

func gain_ap(amount: int) -> void:
	cur_ap = min(cur_ap + amount, AP_CAP)
	vitals_changed.emit()

func take_damage(amount: int) -> void:
	cur_hp = max(0, cur_hp - amount)
	if cur_hp == 0:
		Log.info("HP reached zero")
	vitals_changed.emit()

func heal(amount: int) -> void:
	cur_hp = min(cur_hp + amount, max_hp)
	vitals_changed.emit()

func spend_ap(amount: int) -> void:
	cur_ap -= amount
	vitals_changed.emit()

func spend_mp(amount: int) -> void:
	cur_mp -= amount
	vitals_changed.emit()

func spend_hp_percent(percent: float) -> void:
	var cost: int = max(1, int(max_hp * percent))
	cur_hp = max(0, cur_hp - cost)
	vitals_changed.emit()
