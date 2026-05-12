class_name PlayerCardBar
extends HBoxContainer

signal action_chosen(category: String, item_index: int)

var _cards: Dictionary = {}
var _menus: Dictionary = {}
var _active_actor: CombatCharacter = null

func setup(players: Array) -> void:
	var slots := get_children()
	for i in slots.size():
		var slot: Node = slots[i]
		if i < players.size():
			var actor: CombatCharacter = players[i]
			var card := slot.get_node("CharacterCard") as PlayerCard
			var menu := slot.get_node("ActionMenu") as ActionMenu
			card.setup(actor)
			menu.visible = false
			menu.action_chosen.connect(_on_menu_action_chosen)
			_cards[actor] = card
			_menus[actor] = menu
			slot.visible = true
		else:
			slot.visible = false
	Log.info("PlayerCardBar — slots wired:", _cards.size())

func set_active(actor: CombatCharacter) -> void:
	if _active_actor and _menus.has(_active_actor):
		_menus[_active_actor].visible = false
	_active_actor = actor
	if _menus.has(actor):
		_menus[actor].visible = true
		_menus[actor].reset()

func reset_active() -> void:
	if _active_actor and _menus.has(_active_actor):
		_menus[_active_actor].visible = false
	_active_actor = null

func get_active_menu() -> ActionMenu:
	if _active_actor == null or not _menus.has(_active_actor):
		return null
	return _menus[_active_actor]

func nudge_actor(actor: CombatCharacter, enabled: bool) -> void:
	if _cards.has(actor):
		_cards[actor].nudge(enabled)

func refresh_actor(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].refresh_vitals()

func set_actor_inactive(actor: CombatCharacter) -> void:
	if _cards.has(actor):
		_cards[actor].set_inactive()

func _on_menu_action_chosen(category: String, item_index: int) -> void:
	action_chosen.emit(category, item_index)
