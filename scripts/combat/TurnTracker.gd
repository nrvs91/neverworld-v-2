class_name TurnTracker
## Pure utility for CT/PULSE turn management. No state, no Node base.
##
## CT advances by PULSE/100 each "tick". Ticks are virtual — we loop until
## someone reaches 1.0 rather than advancing one tick per frame.
## Overflow is preserved: a fast actor's head start on the next turn is real.
##
## FUTURE: PULSE-modifying buffs/debuffs and stun effects will require this
##   utility to refresh. When a token changes an actor's PULSE, or a stun
##   freezes CT advance, TurnTracker must react — likely by listening to
##   signals emitted when such tokens are applied or removed.
##   For now, PULSE is treated as static per actor.

static func advance_to_next_turn(actors: Array) -> CombatCharacter:
	while true:
		for actor in actors:
			if actor.vitals.is_downed():
				continue
			
			var pulse: float = actor.stats.stat(CharacterStats.Stat.Pulse)
			var ct_gain: float = pulse / 100.0
			actor.vitals.cur_ct += ct_gain
		
		var ready_actor := _find_ready(actors)
		if ready_actor != null:
			return ready_actor
	
	return null  # unreachable — at least one living actor always exists when called

static func consume_ct(actor: CombatCharacter) -> void:
	actor.vitals.cur_ct -= 1.0
	Log.debug("CT consumed", actor.character_name, actor.vitals.cur_ct)

static func _find_ready(actors: Array) -> CombatCharacter:
	var best_actor: CombatCharacter = null
	var best_pulse: float = 0.0
	
	for actor in actors:
		if actor.vitals.cur_ct < 1.0:
			continue
		
		var actor_pulse: float = actor.stats.stat(CharacterStats.Stat.Pulse)
		
		if best_actor == null:
			best_actor = actor
			best_pulse = actor_pulse
		elif actor_pulse > best_pulse:
			best_actor = actor
			best_pulse = actor_pulse
	
	return best_actor
