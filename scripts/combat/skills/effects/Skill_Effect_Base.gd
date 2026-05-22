class_name Skill_Effect_Base
extends Resource

## ChanceTier is used by RuntimeToken_Damage and CombatCalculator.hit_roll.
## Physical attacks: scales HIT stat in hit formula.
## Ailments (future): raw application probability before resistance.
## Magical damage, heals, buffs: ignored — these always connect.
enum ChanceTier {
	CERTAIN,  # 100% tier
	HIGH,     # 75% tier
	MEDIUM,   # 50% tier
	LOW,      # 25% tier
}

@export var needs_previous_hit: bool = false
