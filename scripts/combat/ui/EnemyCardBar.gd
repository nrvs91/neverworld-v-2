class_name EnemyCardBar
extends HBoxContainer

var _cards: Dictionary = {}

func setup(enemies: Array) -> void:
	var slots := get_children()
	for i in slots.size():
		var card := slots[i] as EnemyCard
		if i < enemies.size():
			var actor: CombatCharacter = enemies[i]
			card.setup(actor)
			card.visible = true
			_cards[actor] = card
		else:
			card.visible = false
	Log.info("EnemyCardBar — cards wired:", _cards.size())

func remove_actor(actor: CombatCharacter) -> void:
	if not _cards.has(actor):
		return
	_cards[actor].visible = false
	_cards.erase(actor)
	Log.info("EnemyCardBar — removed", actor.character_name)

func nudge_actor(actor: CombatCharacter, enabled: bool) -> void:
	if _cards.has(actor):
		_cards[actor].nudge(enabled)

func refresh_actor(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].refresh_vitals()
