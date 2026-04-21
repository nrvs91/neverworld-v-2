class_name MainMenuController
extends Control

func _on_button_new_game_pressed() -> void:
	GameManager.start_new_game()
