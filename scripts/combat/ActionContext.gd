class_name ActionContext
extends RefCounted

const MnemonicResource = preload("res://scripts/combat/skills/MnemonicResource.gd")

var mnemonic: MnemonicResource
var source: CombatCharacter
var targets: Array[CombatCharacter]

var step_results: Array = []
var pending_damage: Array = []
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

var token_snapshot: Dictionary = {}

## Called by INSTANT tokens (RuntimeToken_Damage) after resolving.
## any_hit is ONLY set here — persistent token attachment never touches it.
func record_step(target: CombatCharacter, hit: bool, damage: int, is_crit: bool) -> void:
	step_results.append({target = target, hit = hit, damage = damage, is_crit = is_crit})
	if hit:
		any_hit = true
		total_damage += damage
		pending_damage.append({target = target, damage = damage})
	if is_crit:
		any_crit = true
