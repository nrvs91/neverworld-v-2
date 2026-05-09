extends Node
class_name CharacterCard

@onready var label_name: Label = $CharacterName
@onready var label_hp : Label = $CharacterHP
@onready var label_mp: Label = $CharacterMP
@onready var label_pulse: Label = $CharacterPLS

func display(character: CombatCharacter) -> void:
	label_name.text = character.character_name
	Log.debug("CharacterCard display", character.character_name, character.vitals.cur_hp)
	label_hp.text = "%d / %d" % [character.vitals.cur_hp, character.stats.stat(CharacterStats.Stat.MaxHP)]
	label_mp.text = "%d / %d" % [character.vitals.cur_mp, character.stats.stat(CharacterStats.Stat.MaxMP)]
	label_pulse.text = str(character.stats.stat(CharacterStats.Stat.Pulse))
