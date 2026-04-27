extends Node

# Fired by EncounterManager when a random encounter should start.
# Carries the three pieces of data needed to initialize CombatScene:
#   - composition: which enemies appear, in which slots
#   - environment: the 3D scene to instance as the combat backdrop
#   - bgm:         the audio stream to play during the fight
# Any of the last two may be null (e.g. for the debug F1 hotkey).
signal encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
signal scripted_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
