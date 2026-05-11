class_name EnemyCardBar
extends HBoxContainer

const CharacterCardScene = preload("res://scenes/combat/ui/character_card.tscn")

var _cards: Dictionary = {}

func setup(enemies: Array) -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
	for actor in enemies:
		var card := CharacterCardScene.instantiate() as CharacterCard
		add_child(card)
		card.setup(actor)
		_cards[actor] = card
	Log.info("EnemyCardBar — cards spawned:", _cards.size())

func remove_actor(actor: CombatCharacter) -> void:
	if not _cards.has(actor):
		return
	_cards[actor].queue_free()
	_cards.erase(actor)
	Log.info("EnemyCardBar — removed", actor.character_name)

func nudge_actor(actor: CombatCharacter, enabled: bool) -> void:
	if _cards.has(actor):
		_cards[actor].nudge(enabled)

func refresh_actor(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].refresh_vitals()
