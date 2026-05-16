class_name ActionContext
extends RefCounted

const MnemonicResource = preload("res://scripts/combat/skills/MnemonicResource.gd")

var mnemonic: MnemonicResource
var attacker: CombatCharacter
var primary_target: CombatCharacter

var step_results: Array = []
var tokens_applied: Array = []
var total_damage: int = 0
var any_hit: bool = false
var any_crit: bool = false

## Called by INSTANT tokens (RuntimeToken_Damage) after resolving.
## any_hit is ONLY set here — persistent token attachment never touches it.
func record_step(hit: bool, damage: int, is_crit: bool) -> void:
	step_results.append({hit = hit, damage = damage, is_crit = is_crit})
	if hit:
		any_hit = true
		total_damage += damage
	if is_crit:
		any_crit = true
