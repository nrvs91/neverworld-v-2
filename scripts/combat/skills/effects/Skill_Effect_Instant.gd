class_name Skill_Effect_Instant
extends Skill_Effect_Base

## Token blueprint to fire immediately. Duplicate + fire + discard. Never attached to a character.
## Set power, damage_type, crit_chance etc. directly on the token in the inspector.
@export var token: RuntimeToken
