class_name CombatCalculator
## Pure utility. Takes values in, returns values out. No state, no Node base.

const SkillEffectBase = preload("res://scripts/combat/skills/effects/Skill_Effect_Base.gd")

## Base damage formula:
##   BaseDamage = Σ(stat_i × scaling_i) × (100 / (100 + Def))
## stat_scalings is Array[StatScaling] — sums (stat_value × scaling) across all entries.
## Variance, crit, and token multipliers are applied in resolve_hit.
static func calc_damage(stat_scalings: Array, stats: StatsComponent, def_val: int) -> int:
	var total_atk: float = 0.0
	for entry in stat_scalings:
		var stat_key: CharacterStats.Stat = _stat_from_string(entry.stat)
		var stat_val: int = stats.stat(stat_key)
		total_atk += stat_val * entry.scaling
	return roundi(total_atk * (100.0 / (100.0 + def_val)))

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
		stat_scalings: Array,
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

	var def_stat := CharacterStats.Stat.DefPhys if phys else CharacterStats.Stat.DefMag
	var base := calc_damage(stat_scalings, source.stats, target.stats.stat(def_stat))

	var resist := ResistanceType.State.NONE
	if target.resistance_profile != null:
		resist = target.resistance_profile.get_state(damage_type)

	var token_mult := source.tokens.get_damage_multiplier()
	var total_mult: float = 1.0
	if is_crit:
		total_mult *= 2.0
	total_mult *= resist_multiplier(resist)
	total_mult *= token_mult
	total_mult *= randf_range(0.85, 1.0)

	var final: int = max(1, roundi(base * total_mult))
	return {hit = true, damage = final, is_crit = is_crit, multiplier = total_mult}

static func _tier_multiplier(tier: SkillEffectBase.ChanceTier) -> float:
	match tier:
		SkillEffectBase.ChanceTier.CERTAIN: return 1.0
		SkillEffectBase.ChanceTier.HIGH:    return 0.75
		SkillEffectBase.ChanceTier.MEDIUM:  return 0.50
		SkillEffectBase.ChanceTier.LOW:     return 0.25
	return 1.0

static func _stat_from_string(stat_name: String) -> CharacterStats.Stat:
	match stat_name:
		"Phys.Atk": return CharacterStats.Stat.AtkPhys
		"Magic.Atk": return CharacterStats.Stat.AtkMag
		"MaxHP": return CharacterStats.Stat.MaxHP
		"PULSE": return CharacterStats.Stat.Pulse
		_:
			Log.warn("unknown stat in StatScaling", stat_name, "defaulting to Phys.Atk")
			return CharacterStats.Stat.AtkPhys
