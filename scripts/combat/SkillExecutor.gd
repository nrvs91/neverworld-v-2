class_name SkillExecutor
## Static utility. Resolves a mnemonic's effect steps against a target.
## Creates and returns an ActionContext populated with per-step results.

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")
const SkillEffectBase = preload("res://scripts/combat/skills/effects/Skill_Effect_Base.gd")
const SkillEffectDamage = preload("res://scripts/combat/skills/effects/Skill_Effect_Damage.gd")

static func execute(mnemonic: MnemonicRes, attacker: CombatCharacter, target: CombatCharacter) -> ActionContext:
	var ctx := ActionContext.new()
	ctx.mnemonic = mnemonic
	ctx.attacker = attacker
	ctx.primary_target = target

	for effect in mnemonic.effect_steps:
		if effect.needs_previous_hit and not ctx.any_hit:
			ctx.step_results.append({hit = false, damage = 0, is_crit = false})
			continue
		var result: Dictionary = _resolve_effect(effect, attacker, target)
		ctx.step_results.append(result)
		if result.hit:
			ctx.any_hit = true
			ctx.total_damage += result.damage
		if result.is_crit:
			ctx.any_crit = true

	return ctx

static func _resolve_effect(effect: SkillEffectBase, attacker: CombatCharacter, target: CombatCharacter) -> Dictionary:
	if effect is SkillEffectDamage:
		return _resolve_damage(effect as SkillEffectDamage, attacker, target)
	Log.warn("SkillExecutor — unknown effect type, skipping")
	return {hit = false, damage = 0, is_crit = false}

static func _resolve_damage(effect: SkillEffectDamage, attacker: CombatCharacter, target: CombatCharacter) -> Dictionary:
	var is_phys: bool = _is_physical(effect.damage_type)

	# ChanceTier contract enforcement:
	# Physical (Slash/Pierce/Blunt) — chance_tier scales HIT in the hit formula below.
	# Magical (everything else)     — always hits, chance_tier is not read here at all.
	# true_strike                   — bypasses hit roll regardless of physical/magical.

	# Crit roll first — crit = automatic hit.
	# crit_chance is authored on the effect, not read from attacker stats.
	var is_crit: bool = CombatCalculator.crit_roll(effect.crit_chance)

	# Hit roll (physical only, skipped for magical and true_strike)
	if is_phys and not is_crit and not effect.true_strike:
		var hit_stat: int = attacker.stats.stat(CharacterStats.Stat.Hit)
		var dodge_stat: int = target.stats.stat(CharacterStats.Stat.Dodge)
		if not CombatCalculator.hit_roll(hit_stat, dodge_stat, effect.chance_tier):
			Log.info("SkillExecutor — missed", "%s->%s" % [attacker.character_name, target.character_name])
			return {hit = false, damage = 0, is_crit = false}

	# Resolve the effective damage type:
	# physical + inherit_from_weapon → read from equipped weapon (stub for now)
	# physical + not inherit  → use effect.damage_type directly
	# magical                 → always use effect.damage_type
	var effective_type: ResistanceType.DamageType = effect.damage_type
	if is_phys and effect.inherit_from_weapon:
		effective_type = _get_weapon_damage_type(attacker)

	# Stat routing from effective damage type
	var atk_stat := CharacterStats.Stat.AtkPhys if is_phys else CharacterStats.Stat.AtkMag
	var def_stat := CharacterStats.Stat.DefPhys if is_phys else CharacterStats.Stat.DefMag
	var atk: int = attacker.stats.stat(atk_stat)
	var def_val: int = target.stats.stat(def_stat)
	var raw: int = CombatCalculator.calc_damage(effect.power, atk, def_val)

	# Crit doubles damage
	if is_crit:
		raw *= 2

	# Resistance lookup uses effective_type, not effect.damage_type
	var resist_state := target.resistance_profile.get_state(effective_type)
	var final_damage: int = max(0, int(raw * CombatCalculator.resist_multiplier(resist_state)))

	var summary := "%s->%s %d (crit:%s resist:%s)" % [attacker.character_name, target.character_name,
		final_damage, is_crit, ResistanceType.State.keys()[resist_state]]
	Log.info("SkillExecutor", summary)
	return {hit = true, damage = final_damage, is_crit = is_crit}

static func _is_physical(dt: ResistanceType.DamageType) -> bool:
	return dt == ResistanceType.DamageType.Slash \
		or dt == ResistanceType.DamageType.Pierce \
		or dt == ResistanceType.DamageType.Blunt

static func _get_weapon_damage_type(_attacker: CombatCharacter) -> ResistanceType.DamageType:
	# TODO: read from attacker's equipped weapon once gear system exists.
	# Falls back to effect.damage_type at call site — this stub only fires when
	# inherit_from_weapon = true and no gear system is in place yet.
	return ResistanceType.DamageType.Slash
