class_name PlayerData
extends CombatData

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

@export var character_portrait: Texture2D
@export var growth_table: GrowthTable
@export var allowed_gear: Array[EquipmentType.Flags] = []
@export var starting_level: int = 1
@export var mnemonics: Array[MnemonicRes] = []