class_name PlayerCardBar
extends HBoxContainer

signal action_chosen(category: String, item_index: int)

const CharacterCardScene = preload("res://scenes/combat/ui/character_card.tscn")
const ActionMenuScene = preload("res://scenes/combat/ui/action_menu.tscn")

var _cards: Dictionary = {}
var _menus: Dictionary = {}
var _active_actor: CombatCharacter = null

func setup(players: Array) -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
	_menus.clear()
	for actor in players:
		var slot := VBoxContainer.new()
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(slot)

		var card := CharacterCardScene.instantiate() as CharacterCard
		slot.add_child(card)
		card.setup(actor)
		_cards[actor] = card

		var menu := ActionMenuScene.instantiate() as ActionMenu
		slot.add_child(menu)
		menu.visible = false
		menu.action_chosen.connect(_on_menu_action_chosen)
		_menus[actor] = menu
	Log.info("PlayerCardBar — slots spawned:", _cards.size())

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
