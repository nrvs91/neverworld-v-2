class_name SkillButton
extends CombatButton

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

@onready var _name_label: Label = $MarginContainer/Layout/SkillName
@onready var _cost_ap: Label = $MarginContainer/Layout/Cost_1
@onready var _cost_resource: Label = $MarginContainer/Layout/Cost_2
@onready var _background = $ButtonBackground

var mnemonic: MnemonicRes = null
var is_selected: bool = false

func _ready() -> void:
	super._ready()
	if _background and _background.material:
		_background.material = _background.material.duplicate()

## Skills always cost exactly two resources: AP + either HP or MP.
## vitals is needed to calculate the real HP cost and to check affordability.
func setup(m: MnemonicRes, vitals: VitalsComponent, precondition_met: bool = true) -> void:
	mnemonic = m
	_name_label.text = m.mnemonic_name
	_cost_ap.text = str(m.ap_cost) + "AP"

	# Resolve the second cost — HP takes priority if both are somehow non-zero
	var hp_cost: int = max(1, int(vitals.max_hp * m.hp_cost_percent)) if m.hp_cost_percent > 0.0 else 0
	if hp_cost > 0:
		_cost_resource.text = str(hp_cost) + "HP"
		_cost_resource.visible = true
	elif m.mp_cost > 0:
		_cost_resource.text = str(m.mp_cost) + "MP"
		_cost_resource.visible = true
	else:
		_cost_resource.visible = false

	# Grey out if the actor can't afford either cost
	var can_afford: bool = vitals.cur_ap >= m.ap_cost \
		and (hp_cost == 0 or vitals.cur_hp > hp_cost) \
		and (m.mp_cost == 0 or vitals.cur_mp >= m.mp_cost)
	modulate.a = 1.0 if (can_afford and precondition_met) else 0.4

func set_selected(selected: bool) -> void:
	is_selected = selected
