class_name ActionContext
extends RefCounted

const MnemonicResource = preload("res://scripts/combat/skills/MnemonicResource.gd")

var mnemonic: MnemonicResource
var source: CombatCharacter
var target: CombatCharacter

var step_results: Array = []
var tokens_applied: Array = []
var total_damage: int = 0
var any_hit: bool = false
var any_crit: bool = false

# Reference to the primary action's context. Set on reaction contexts so tokens
# can read the triggering event for target resolution (e.g. COUNTER hits the source).
var trigger_context: ActionContext = null

# Set by PRE_EXECUTION reactions (e.g. Premonition) to nullify the primary action.
# ActionPipeline checks this after the pre-pass and skips SkillExecutor if true.
var negated: bool = false

# Set by ActionPipeline when validation fails (source downed, stunned, etc.).
# Used for UI feedback — "cancelled" is distinct from "negated" (no resource cost).
var cancelled: bool = false

# Populated by ActionPipeline pre-pass. Holds RuntimeToken objects that fire before primary.
var pre_queue: Array = []

# Populated by ActionPipeline post-pass. Holds RuntimeToken objects that fire after primary.
var post_queue: Array = []

## Called by INSTANT tokens (RuntimeToken_Damage) after resolving.
## any_hit is ONLY set here — persistent token attachment never touches it.
func record_step(hit: bool, damage: int, is_crit: bool) -> void:
	step_results.append({hit = hit, damage = damage, is_crit = is_crit})
	if hit:
		any_hit = true
		total_damage += damage
	if is_crit:
		any_crit = true
