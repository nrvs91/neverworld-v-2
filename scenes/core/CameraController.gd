extends Camera3D

func _ready() -> void:
	look_at(get_parent().global_position)
 
