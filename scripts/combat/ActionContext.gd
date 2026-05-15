class_name ActionContext
extends RefCounted

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

var mnemonic: MnemonicRes
var attacker: CombatCharacter
var primary_target: CombatCharacter

var step_results: Array = []
var total_damage: int = 0
var any_hit: bool = false
var any_crit: bool = false
var ailments_applied: Array = []
