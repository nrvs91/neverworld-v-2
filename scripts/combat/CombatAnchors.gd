class_name CombatAnchors
extends Node

var player_party: Node3D
var enemy_party: Node3D
var middle: Node3D

func register(p: Node3D, e: Node3D, m: Node3D) -> void:
	player_party = p
	enemy_party = e
	middle = m
	Log.info("CombatAnchors — registered")

func clear() -> void:
	player_party = null
	enemy_party = null
	middle = null
	Log.info("CombatAnchors — cleared")
