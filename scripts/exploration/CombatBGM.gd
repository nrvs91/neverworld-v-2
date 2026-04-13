class_name CombatBGM
extends Node

# Authored per-map. The BGM track played during combat in this area.
# Stays a data holder for now; room to grow into crossfade / boss-phase logic.
@export var stream: AudioStream