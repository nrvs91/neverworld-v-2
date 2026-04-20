extends CanvasLayer
class_name ScreenFader

signal fade_out_done
signal fade_in_done

@onready var rect: ColorRect = $ColorRect
@onready var anim: AnimationPlayer = $AnimationPlayer

func fade_out() -> void:
	anim.play("fade_out")
	await fade_out_done

func fade_in() -> void:
	anim.play("fade_in")
	await fade_in_done
