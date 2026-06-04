extends Node

const MnemonicRes = preload("res://scripts/combat/skills/MnemonicResource.gd")
const RuntimeToken = preload("res://scripts/combat/tokens/RuntimeToken.gd")
const ActionContext = preload("res://scripts/combat/ActionContext.gd")

# Fired by EncounterManager when a random encounter should start.
# Carries the three pieces of data needed to initialize CombatScene:
#   - composition: which enemies appear, in which slots
#   - environment: the 3D scene to instance as the combat backdrop
#   - bgm:         the audio stream to play during the fight
# Any of the last two may be null (e.g. for the debug F1 hotkey).
signal encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)
signal scripted_encounter_triggered(composition: CombatConfig, environment: PackedScene, bgm: AudioStream)

# CombatFSM signals — emitted by CombatFSM, consumed by UI FSM and other listeners
signal combat_started
signal turn_started(actor: CombatCharacter)
signal please_select_action(actor: CombatCharacter)
signal action_selected(mnemonic: MnemonicRes, target: CombatCharacter)
signal action_animation_complete
signal action_hit_frame
signal action_executed(actor: CombatCharacter, targets: Array[CombatCharacter], damage: int, mnemonic: MnemonicRes)
signal action_resolved(context: ActionContext)
signal combat_text_shown(target: CombatCharacter, text: String)
signal actor_downed(actor: CombatCharacter)
signal turn_ended(actor: CombatCharacter)
signal combat_ended(player_won: bool)

signal dot_ticked(token: RuntimeToken, context: ActionContext)
signal action_announced(text: String)
