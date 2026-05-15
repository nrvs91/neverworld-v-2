class_name ActionMenu
extends VBoxContainer

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

signal action_chosen(category: String, item_index: int)

const CATEGORIES: Array[String] = ["ACT", "ITEM", "WAIT", "RUN"]

const SKILL_BUTTON := preload("res://scenes/UI/skill_button.tscn")
const ITEM_BUTTON := preload("res://scenes/UI/item_button.tscn")

@onready var _menu_name: Label = $Frame/MenuName
@onready var _skill_menu: VBoxContainer = $ContentArea/SkillMenu
@onready var _item_menu: VBoxContainer = $ContentArea/ItemMenu
@onready var _wait_menu: VBoxContainer = $ContentArea/WaitMenu
@onready var _run_menu: VBoxContainer = $ContentArea/RunMenu

var _menus: Array[VBoxContainer]
var _category_index: int = 0
var _item_index: int = 0

var _skill_mnemonics: Array = []

func _ready() -> void:
	_menus = [_skill_menu, _item_menu, _wait_menu, _run_menu]
	_refresh_display()

func populate(skills: Array, items: Array, vitals: VitalsComponent) -> void:
	_skill_mnemonics = skills
	for child in _skill_menu.get_children():
		_skill_menu.remove_child(child)
		child.queue_free()
	for mnemonic in skills:
		var btn := SKILL_BUTTON.instantiate() as SkillButton
		btn.setup(mnemonic, vitals)
		_skill_menu.add_child(btn)

	for child in _item_menu.get_children():
		_item_menu.remove_child(child)
		child.queue_free()
	for item in items:
		var btn: Button = ITEM_BUTTON.instantiate()
		# TODO: btn.setup(item) once ItemResource format is defined
		_item_menu.add_child(btn)

	_item_index = 0
	_refresh_display()

func reset() -> void:
	_category_index = 0
	_item_index = 0
	_refresh_display()

func next_category() -> void:
	_category_index = (_category_index + 1) % CATEGORIES.size()
	_item_index = 0
	_refresh_display()

func prev_category() -> void:
	_category_index = (_category_index - 1 + CATEGORIES.size()) % CATEGORIES.size()
	_item_index = 0
	_refresh_display()

func next_item() -> void:
	var items := _active_items()
	if items.is_empty():
		return
	_item_index = (_item_index + 1) % items.size()
	_refresh_display()

func prev_item() -> void:
	var items := _active_items()
	if items.is_empty():
		return
	_item_index = (_item_index - 1 + items.size()) % items.size()
	_refresh_display()

func confirm() -> void:
	action_chosen.emit(CATEGORIES[_category_index], _item_index)
	Log.info("ActionMenu chosen", CATEGORIES[_category_index], _item_index)

func _active_items() -> Array:
	var category := CATEGORIES[_category_index]
	if category != "ACT" and category != "ITEM":
		return []
	return _menus[_category_index].get_children()

func get_selected_mnemonic() -> MnemonicRes:
	if _skill_mnemonics.is_empty() or _item_index >= _skill_mnemonics.size():
		return null
	return _skill_mnemonics[_item_index]

func _refresh_display() -> void:
	_menu_name.text = CATEGORIES[_category_index]
	for i in _menus.size():
		_menus[i].visible = (i == _category_index)
	var items := _active_items()
	for i in items.size():
		(items[i] as Button).button_pressed = (i == _item_index)
	Log.debug("ActionMenu", CATEGORIES[_category_index], _item_index)
