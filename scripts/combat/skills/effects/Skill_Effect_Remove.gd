class_name Skill_Effect_Remove
extends Skill_Effect_Base

## Remove all tokens of a given type from the target (cleanse, dispel, purge).
## Set amount to -1 to remove all instances; set to N to remove exactly N.
@export var token_type: String = ""
@export var amount: int = -1
