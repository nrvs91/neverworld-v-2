class_name RuntimeToken
extends RefCounted

enum Trigger {
	INSTANT,
	ON_TURN_START,
	ON_DAMAGE_TAKEN,  # stub — not dispatched yet (COUNTER, BRACE)
	ON_ALLY_HIT,      # stub — not dispatched yet (VIGIL, FOLLOW UP)
	PRE_EXECUTION,    # stub — not dispatched yet (PREMONITION, COVER)
}

var token_type: String = ""
var trigger: Trigger = Trigger.INSTANT
var charges: int = 1
var source: CombatCharacter = null
var owner: CombatCharacter = null

## Called by SkillExecutor for INSTANT tokens during mnemonic resolution.
## Reads context.any_hit for conditional chaining. Writes result via context.record_step().
func fire(_context: ActionContext) -> void:
	pass

## Called by ActiveTokens.tick_turn_start() for ON_TURN_START tokens.
## ActiveTokens creates one fresh context per token before calling this.
## mnemonic/attacker/primary_target are null on that context — read self.owner/self.source instead.
func tick(_context: ActionContext) -> void:
	pass
