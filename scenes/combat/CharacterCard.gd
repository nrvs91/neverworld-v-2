extends Node
class_name CharacterCard

@onready var label_name: Label = $CharacterName
@onready var label_hp : Label = $CharacterHP
@onready var label_mp: Label = $CharacterMP

func display(character: CombatCharacter) -> void:
	label_name.text = character.character_name
	Log.info("CharacterCard display", character.character_name, character.vitals.cur_hp)
	label_hp.text = "%d / %d" % [character.vitals.cur_hp, character.stats.stat(CharacterStats.Stat.MaxHP)]
	label_mp.text = "%d / %d" % [character.vitals.cur_mp, character.stats.stat(CharacterStats.Stat.MaxMP)]
