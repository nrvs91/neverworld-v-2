class_name PlayerData
extends CombatData

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")

@export_group("Vitals")
@export var MaxMP: int = 1

@export_group("Offense")
@export var AtkPhys: int = 1
@export var AtkMag: int = 1

@export var character_portrait: Texture2D
@export var growth_table: GrowthTable
@export var allowed_gear: Array[EquipmentType.Flags] = []
@export var starting_level: int = 1
@export var mnemonics: Array[MnemonicRes] = []