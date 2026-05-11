class_name ActionMenu
extends VBoxContainer

signal action_chosen(category: String, item_index: int)

const CATEGORIES: Array[String] = ["ACT", "ITEM", "WAIT", "RUN"]

@onready var skill_list: VBoxContainer = $SkillList
@onready var _category_buttons: Array = []

var _category_index: int = 0
var _item_index: int = 0

func _ready() -> void:
	for btn in $Categories.get_children():
		_category_buttons.append(btn)

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
	var items := _active_skill_buttons()
	if items.is_empty():
		return
	_item_index = (_item_index + 1) % items.size()
	_refresh_display()

func prev_item() -> void:
	var items := _active_skill_buttons()
	if items.is_empty():
		return
	_item_index = (_item_index - 1 + items.size()) % items.size()
	_refresh_display()

func confirm() -> void:
	var category := CATEGORIES[_category_index]
	if category == "ITEM" or category == "RUN":
		Log.info("ActionMenu — stub, no action", category)
		return
	action_chosen.emit(category, _item_index)
	Log.info("ActionMenu chosen", category, _item_index)

func _active_skill_buttons() -> Array:
	if CATEGORIES[_category_index] != "ACT":
		return []
	return skill_list.get_children().filter(func(b: Button) -> bool: return not b.disabled)

func _refresh_display() -> void:
	var category := CATEGORIES[_category_index]
	for i in _category_buttons.size():
		_category_buttons[i].button_pressed = (i == _category_index)
	var is_act := (category == "ACT")
	skill_list.visible = is_act
	if is_act:
		var items := _active_skill_buttons()
		for i in items.size():
			items[i].button_pressed = (i == _item_index)
	Log.debug("ActionMenu", category, _item_index)
