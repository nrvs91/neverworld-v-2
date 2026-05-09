class_name CombatCalculator
## Pure utility. Takes combatants in, returns resolved values out. No state, no Node base.

## Basic physical attack using the GDD damage formula:
##   damage = Power × AtkPhys / (DefPhys + 10) × Random(0.85, 1.0)
## Power is fixed at 30 for the stub basic attack (no mnemonic yet).
static func base_attack(attacker: CombatCharacter, target: CombatCharacter) -> int:
	const POWER: int = 30
	var atk: float = attacker.stats.stat(CharacterStats.Stat.AtkPhys)
	var def: float = target.stats.stat(CharacterStats.Stat.DefPhys)
	var variance: float = randf_range(0.85, 1.0)
	var result := int(POWER * atk / (def + 10.0) * variance)
	return max(1, result)
