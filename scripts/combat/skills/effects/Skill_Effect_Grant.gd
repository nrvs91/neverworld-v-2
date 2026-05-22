class_name Skill_Effect_Grant
extends Skill_Effect_Base

## Token blueprint to attach to the target. Creates `amount` separate instances.
## Each instance fires once when its trigger condition is met, then is removed.
@export var token: RuntimeToken
@export var amount: int = 1
