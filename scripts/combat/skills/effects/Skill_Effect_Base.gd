class_name Skill_Effect_Base
extends Resource

## ChanceTier is a universal accuracy/reliability descriptor.
## Its meaning is resolved by the CONSUMING effect type — not by this base class.
##
## Skill_Effect_Damage (physical):
##   Scales the attacker's HIT stat in the GDD hit formula:
##   hitChance = clamp((attacker.HIT × tier%) / defender.DODGE, 5%, 95%)
##   CERTAIN = full HIT / DODGE ratio. Still not guaranteed — only true_strike is.
##
## Skill_Effect_Ailment / Skill_Effect_Dot (future):
##   IS the raw application probability before resistance:
##   appChance = tier% × resist_multiplier
##   CERTAIN = 100% application (before resistance can reduce it).
##
## Skill_Effect_Damage (magical), heals, buffs, HoT, Mark, etc.:
##   IGNORED. These effects always connect — ChanceTier has no effect on them.
enum ChanceTier {
	CERTAIN,  # 100% tier — physical: full HIT/DODGE ratio; ailment: guaranteed before resist
	HIGH,     # 75% tier
	MEDIUM,   # 50% tier
	LOW,      # 25% tier
}

@export var chance_tier: ChanceTier = ChanceTier.HIGH
@export var needs_previous_hit: bool = false
@export var true_strike: bool = false
