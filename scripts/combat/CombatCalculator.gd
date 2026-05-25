class_name CombatCalculator
## Pure utility. Takes values in, returns values out. No state, no Node base.

const SkillEffectBase = preload("res://scripts/combat/skills/effects/Skill_Effect_Base.gd")

## Raw damage formula from GDD:
##   damage = Power × Atk / (Def + 10) × Random(0.85, 1.0)
static func calc_damage(power: int, atk: int, def_val: int) -> int:
	var variance: float = randf_range(0.85, 1.0)
	return max(1, int(power * atk / (def_val + 10.0) * variance))

## Crit roll. Returns true if the attack crits.
## Crit = automatic hit + 2× damage. Must be rolled BEFORE the hit roll.
## crit_chance comes from RuntimeToken_Damage, NOT from a character stat.
static func crit_roll(crit_chance: int) -> bool:
	return randf() < crit_chance / 100.0

## Hit roll. Returns true if the attack connects.
## GDD formula: clamp((attacker.HIT × ChanceTier%) / defender.DODGE, 5%, 95%)
static func hit_roll(hit_stat: int, dodge_stat: int, tier: SkillEffectBase.ChanceTier) -> bool:
	var tier_mult: float = _tier_multiplier(tier)
	var chance: float = clampf((hit_stat * tier_mult) / float(max(1, dodge_stat)), 0.05, 0.95)
	return randf() <= chance

## Resistance multiplier for damage or ailment application.
static func resist_multiplier(state: ResistanceType.State) -> float:
	match state:
		ResistanceType.State.WEAK:      return 2.0
		ResistanceType.State.RESISTANT: return 0.5
		ResistanceType.State.IMMUNE:    return 0.0
		_:                              return 1.0

static func is_physical(dt: ResistanceType.DamageType) -> bool:
	return dt in [ResistanceType.DamageType.Slash, ResistanceType.DamageType.Pierce, ResistanceType.DamageType.Blunt]

## Full hit-crit-damage pipeline. Returns {hit, damage, is_crit, multiplier}.
## Rolls crit first, then hit (skipped for magic or true_strike), then resolves
## stats, resist, and the source's active damage multiplier tokens.
static func resolve_hit(
		power: int,
		damage_type: ResistanceType.DamageType,
		crit_chance: int,
		chance_tier: SkillEffectBase.ChanceTier,
		source: CombatCharacter,
		target: CombatCharacter,
		true_strike: bool = false
) -> Dictionary:
	var phys := is_physical(damage_type)
	var is_crit := phys and crit_roll(crit_chance)

	if phys and not is_crit and not true_strike:
		var hit := source.stats.stat(CharacterStats.Stat.Hit)
		var dodge := target.stats.stat(CharacterStats.Stat.Dodge)
		if not hit_roll(hit, dodge, chance_tier):
			return {hit = false, damage = 0, is_crit = false, multiplier = 1.0}

	var atk_stat := CharacterStats.Stat.AtkPhys if phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if phys else CharacterStats.Stat.DefMag
	var raw := calc_damage(power, source.stats.stat(atk_stat), target.stats.stat(def_stat))

	if is_crit:
		raw *= 2

	var resist := ResistanceType.State.NONE
	if target.resistance_profile != null:
		resist = target.resistance_profile.get_state(damage_type)

	var mult := source.tokens.get_damage_multiplier()
	var final: int = max(0, int(raw * resist_multiplier(resist) * mult))
	return {hit = true, damage = final, is_crit = is_crit, multiplier = mult}

static func _tier_multiplier(tier: SkillEffectBase.ChanceTier) -> float:
	match tier:
		SkillEffectBase.ChanceTier.CERTAIN: return 1.0
		SkillEffectBase.ChanceTier.HIGH:    return 0.75
		SkillEffectBase.ChanceTier.MEDIUM:  return 0.50
		SkillEffectBase.ChanceTier.LOW:     return 0.25
	return 1.0
